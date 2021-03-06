#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_sv_2pv_flags
#include "ppport.h"

#include "hook_op_check.h"
#include "hook_op_annotation.h"

#include "stdlib.h" /* for getenv */
#include "string.h" /* for strchr and strrchr */
/* #define NDEBUG */
#include "assert.h"

#define MYSUBS_INSTALLED "mysubs"

#define MYSUBS_ENABLED(table, svp)                                                    \
    ((PL_hints & 0x20000) &&                                                          \
    (table = GvHV(PL_hintgv)) &&                                                      \
    (svp = hv_fetch(table, MYSUBS_INSTALLED, sizeof(MYSUBS_INSTALLED) - 1, FALSE)) && \
    *svp &&                                                                           \
    SvOK(*svp) &&                                                                     \
    SvROK(*svp) &&                                                                    \
    SvRV(*svp) &&                                                                     \
    SvTYPE(SvRV(*svp)) == SVt_PVHV)

#define MYSUBS_REDO 1

typedef struct {
    SV * fqname;
    const char * name;
    STRLEN len;
    CV *cv;
} MySubsData;

STATIC CV * mysubs_get_cv(pTHX_ SV *rv);
STATIC MySubsData * mysubs_data_new(pTHX_ SV * const fqname, const char *name, STRLEN len, CV *cv);
STATIC OP * mysubs_check_entersub(pTHX_ OP * o, void * user_data);
STATIC OP * mysubs_check_prototype(pTHX_ OP * o, void * user_data);
STATIC OP * mysubs_gv(pTHX);
STATIC OP * mysubs_prototype(pTHX);
STATIC void mysubs_data_free(pTHX_ void *vp);
STATIC void mysubs_enter();
STATIC void mysubs_leave();
STATIC void mysubs_set_autoload(pTHX_ const GV * const gv, const MySubsData *data);

STATIC hook_op_check_id mysubs_check_entersub_id = 0;
STATIC hook_op_check_id mysubs_check_prototype_id = 0;
STATIC OPAnnotationGroup MYSUBS_ANNOTATIONS = NULL;
STATIC U32 MYSUBS_COMPILING = 0;
STATIC U32 MYSUBS_DEBUG = 0;

STATIC MySubsData * mysubs_data_new(pTHX_ SV * const fqname, const char *name, STRLEN len, CV *cv) {
    MySubsData *data;

    Newx(data, 1, MySubsData);

    if (!data) {
        croak("couldn't allocate annotation data");
    }

    data->fqname = fqname;
    data->name = name;
    data->len = len;
    data->cv = cv;

    return data;
}

STATIC void mysubs_data_free(pTHX_ void *vp) {
    MySubsData *data = (MySubsData *)vp;

    SvREFCNT_dec(data->fqname);
    Safefree(data);
}

STATIC OP * mysubs_check_entersub(pTHX_ OP * o, void * user_data) {
    HV * table;
    SV ** svp;

    PERL_UNUSED_VAR(user_data);

    if (MYSUBS_ENABLED(table, svp)) {
        OP *cvop;
        OP *prev = ((cUNOPo->op_first->op_sibling) ? cUNOPo : ((UNOP*)cUNOPo->op_first))->op_first;
        OP *o2 = prev->op_sibling;

        for (cvop = o2; cvop->op_sibling; cvop = cvop->op_sibling); /* find the CV-locator op */

        while (cvop->op_type == OP_NULL) {
            /* warn("traversing null OPs for 0x%x", (PTRV)o); */
            cvop = (OP*)((UNOP*)cvop)->op_first;
        }

        if (cvop->op_type == OP_GV) {
            SVOP *gvop = (SVOP *)cvop;

            /*
             * invocations of recursive and AUTOLOAD subs are compiled as GVOPs before
             * perl has anything to fill the CV slot with
             *
             * in both cases we splice in our own version of OP_GV that (at runtime) a)
             * uninstalls itself if the CV slot has been filled b) sets the CV slot to
             * the lexical sub if one is found or c) locates the lexical AUTOLOAD sub
             * if one was defined
             *
             * FIXME: document the fact that recursive/AUTOLOAD mysubs will only work if mysubs
             * is already enabled i.e. if there has been a previous "use mysubs" statement
             *
             * FIXME:
             *
             *     use mysubs foo => sub { ... };
             *     no mysubs;
             *     foo();
             *     use mysubs foo => sub { ... };
             *
             * XXX With runtime resolution of "early" lexical subs that foo() shouldn't work, but does.
             * At least document this.
             *
             * recursion works fine when importing subs from a module because the imported subs
             * can easily refer to themselves
             *
             * solution: add support for a keyword e.g. "private" or "mysub"
             * with a keyword like "private" or "mysub" we can easily stop parsing after the word
             * and turn on the mysubs pragma for subsequent literals e.g.
             *
             *     private AUTOSUB { ... }
             *
             * becomes:
             *
             *     use mysubs; use mysubs AUTOSUB => sub { ... };
             *
             * So:
             *
             *     mysub foo () is recursive { }
             *
             * becomes:
             *
             *     use mysub foo => undef; use mysub foo { ... foo() }
             */
            if (gvop->op_private & OPpEARLY_CV) {
                char *fqname, *name;
                STRLEN fqlen;
                SV *key;
                HE *he;
                HV *installed = (HV *)SvRV(*svp);
                SV *fqname_sv = newSVpvn("", 0);

                gv_efullname3(fqname_sv, cGVOPx_gv(gvop), NULL);
                /* warn("glob full name: '%s'", SvPVX(fqname_sv)); */

                fqname = SvPV(fqname_sv, fqlen);
                name = strrchr(fqname, ':') + 1;
                assert(name);

                key = sv_2mortal(newSVpvn(fqname, name - fqname));
                sv_catpvn(key, "AUTOLOAD", 8);
                /* warn("testing name: '%s'", SvPVX(key)); */

                he = hv_fetch_ent(installed, key, FALSE, 0);

                if (he) {
                    CV * cv;

                    cv = mysubs_get_cv(aTHX_ HeVAL(he));

                    if (cv) {
                        MySubsData *data;
                        data = mysubs_data_new(aTHX_ fqname_sv, name, fqlen - (name - fqname), cv);
                        /* warn("annotating gvop for %s", fqname); */
                        op_annotate(MYSUBS_ANNOTATIONS, (OP *)gvop, data, mysubs_data_free);
                        gvop->op_ppaddr = mysubs_gv;
                    }
                } else {
                    SvREFCNT_dec(fqname_sv);
                }
            }
        }
    }

    return o;
}

STATIC OP *mysubs_gv(pTHX) {
    dSP;
    OPAnnotation *annotation = op_annotation_get(MYSUBS_ANNOTATIONS, PL_op);

    if (GvCV(cGVOP_gv)) {
        PL_op->op_ppaddr = annotation->op_ppaddr; /* XXX use the annotation *before* deleting it! */
        op_annotation_delete(aTHX_ MYSUBS_ANNOTATIONS, PL_op);
        return PL_op->op_ppaddr(aTHX);
    } else {
        MySubsData *data = annotation->data;
        XPUSHs((SV *)data->cv);
        mysubs_set_autoload(aTHX_ cGVOP_gv, data);
        RETURN;
    }
}

STATIC void mysubs_set_autoload(pTHX_ const GV * const gv, const MySubsData *data) {
    CV *cv = data->cv;

#ifndef CvISXSUB
#  define CvISXSUB(cv) (CvXSUB(cv) ? TRUE : FALSE)
#endif

    assert(CvROOT(cv) || CvISXSUB(cv));

    /* <copypasta file="gv.c" function="gv_autoload4"> */

#ifndef USE_5005THREADS
    if (CvISXSUB(cv)) {
        /* rather than lookup/init $AUTOLOAD here
         * only to have the XSUB do another lookup for $AUTOLOAD
         * and split that value on the last '::',
         * pass along the same data via some unused fields in the CV
         */

/* chocolateboy 2011-03-04: portability fix for perl 5.13 */
#ifdef CvSTASH_set
        CvSTASH_set(cv, GvSTASH(gv));
#else
        CvSTASH(cv) = GvSTASH(gv);
#endif
        SvPV_set(cv, (char *)data->name); /* cast to lose constness warning */
        SvCUR_set(cv, data->len);
        return;
    } else
#endif

    {
        HV* varstash;
        GV* vargv;
        SV* varsv;

        /*
         * Given &FOO::AUTOLOAD, set $FOO::AUTOLOAD to desired function name.
         * The subroutine's original name may not be "AUTOLOAD", so we don't
         * use that, but for lack of anything better we will use the sub's
         * original package to look up $AUTOLOAD.
         */
        varstash = GvSTASH(CvGV(cv));
        vargv = *(GV **)hv_fetch(varstash, "AUTOLOAD", 8, TRUE);

        ENTER;

#ifdef USE_5005THREADS /* chocolateboy: shouldn't be defined after 5.8.x */
        sv_lock((SV *)varstash);
#endif

        if (!isGV(vargv)) {
            gv_init(vargv, varstash, "AUTOLOAD", 8, FALSE);
#ifdef PERL_DONT_CREATE_GVSV
            GvSV(vargv) = newSV(0);
#endif
        }
        LEAVE;

#ifndef GvSVn
#  ifdef PERL_DONT_CREATE_GVSV
#    define GvSVn(gv) (*(GvGP(gv)->gp_sv ? &(GvGP(gv)->gp_sv) : &(GvGP(gv_SVadd(gv))->gp_sv)))
#  else
#    define GvSVn(gv) GvSV(gv)
#  endif
#endif

        varsv = GvSVn(vargv);

#ifdef USE_5005THREADS /* chocolateboy: shouldn't be defined after 5.8.x */
        sv_lock(varsv);
#endif

        /*
         * Ensure SvSETMAGIC() is called if necessary. In particular, to clear
         * tainting if $FOO::AUTOLOAD was previously tainted, but is not now.
         */
        sv_setpv_mg(varsv, SvPVX(data->fqname));
    }

    /* </copypasta> */
}

STATIC OP * mysubs_check_prototype(pTHX_ OP * o, void * user_data) {
    HV * table;
    SV ** svp;

    PERL_UNUSED_VAR(user_data);

    /*
     * perl doesn't currently have a checker for OP_PROTOTYPE
     * (i.e. it uses Perl_ck_null), so usually this isn't needed
     * but it may change in future, or another module may change the OP
     */
    if ((o->op_type == OP_PROTOTYPE) && MYSUBS_ENABLED(table, svp)) {
        op_annotate(MYSUBS_ANNOTATIONS, o, SvRV(*svp), NULL);
        o->op_ppaddr = mysubs_prototype;
    }

    return o;
}

STATIC OP * mysubs_prototype(pTHX) {
    dSP;
    OPAnnotation * const annotation = op_annotation_get(MYSUBS_ANNOTATIONS, PL_op);
    SV * sv = TOPs;

    SvGETMAGIC(sv);

    if (SvPOK(sv)) {
        SV ** svp;
        STRLEN len;
        SV * fqname = NULL;
        HV * installed = (HV *)annotation->data;
        const char * s = SvPV_const(sv, len);

        assert(installed);
        assert(SvTYPE(installed) == SVt_PVHV);

        if (strchr(s, '\'')) {
            STRLEN i;
            /* there are more efficient ways to do this, but this works without tears in older perls */
            fqname = sv_2mortal(newSVpvn("", 0));

            for (i = 0; i < len; ++i) {
                if (s[i] == '\'') {
                    sv_catpvs(fqname, "::");
                } else {
                    sv_catpvn(fqname, s + i, 1);
                }
            }
        } else if (strchr(s, ':')) {
            fqname = sv;
        } else if (MYSUBS_COMPILING) { /* compile-time */
            fqname = newSVpvf("%s::%s", HvNAME(PL_curstash ? PL_curstash : PL_defstash), s);
        } else { /* runtime */
            fqname = newSVpvf("%s::%s", CopSTASHPV(PL_curcop) , s);
        }

        if (MYSUBS_DEBUG) {
            warn("mysubs: looking up prototype: %s", SvPV_nolen_const(fqname));
        }

        svp = hv_fetch(installed, SvPV_nolen_const(fqname), SvCUR(fqname), 0);

        if (svp && *svp) {
            CV * cv = mysubs_get_cv(aTHX_ *svp);

            if (cv) {
                if (MYSUBS_DEBUG) {
                    warn("mysubs: found prototype");
                }
                SETs((SV *)cv);
            }
        }

    }

    return annotation->op_ppaddr(aTHX);
}

STATIC CV * mysubs_get_cv(pTHX_ SV *rv) {
    CV * cv = NULL;

    if (rv && SvOK(rv) && SvROK(rv) && SvRV(rv) && (SvTYPE(SvRV(rv)) == SVt_PVAV)) {
        AV * pair;
        SV **svp;

        pair = (AV *)(SvRV(rv));
        svp = av_fetch(pair, MYSUBS_REDO, 0); /* $installed->{$fqname}->[REDO] */

        if (svp && *svp && isGV(*svp)) {
            GV * gv = (GV *)*svp;

            if (GvCV(gv)) {
                cv = GvCV(gv);
            }
        }
    }

    return cv;
}

STATIC void mysubs_enter() {
    if (MYSUBS_COMPILING != 0) {
        croak("mysubs: scope overflow");
    } else {
        MYSUBS_COMPILING = 1;
        mysubs_check_prototype_id = hook_op_check(OP_PROTOTYPE, mysubs_check_prototype, NULL);
        mysubs_check_entersub_id = hook_op_check(OP_ENTERSUB, mysubs_check_entersub, NULL);
    }
}

STATIC void mysubs_leave() {
    if (MYSUBS_COMPILING != 1) {
        croak("mysubs: scope underflow");
    } else {
        MYSUBS_COMPILING = 0;
        hook_op_check_remove(OP_PROTOTYPE, mysubs_check_prototype_id);
        hook_op_check_remove(OP_ENTERSUB, mysubs_check_entersub_id);
    }
}

MODULE = mysubs                PACKAGE = mysubs

BOOT:
    if (getenv("PERL_MYSUBS_DEBUG")) {
        MYSUBS_DEBUG = 1;
    }

    MYSUBS_ANNOTATIONS = op_annotation_group_new();

void
END()
    CODE:
        if (MYSUBS_ANNOTATIONS) { /* make sure it was initialised */
            op_annotation_group_free(aTHX_ MYSUBS_ANNOTATIONS);
        }

SV *
xs_get_debug()
    PROTOTYPE:
    CODE:
        RETVAL = newSViv(MYSUBS_DEBUG);
    OUTPUT:
        RETVAL

void
xs_set_debug(SV * dbg)
    PROTOTYPE:$
    CODE:
        MYSUBS_DEBUG = SvIV(dbg);

void
xs_cache(SV* sv)
    PROTOTYPE:$
    CODE:
        ++SvREFCNT(SvRV(sv));

void
xs_glob_eq(GV * gv1, GV * gv2)
    PROTOTYPE:$$
    CODE:
        if (isGV(gv1) && isGV(gv2)) {
            XSRETURN_UV(GvGP(gv1) == GvGP(gv2)); /* glob, glob */
        } else if (!(isGV(gv1) || isGV(gv2))) {
            XSRETURN_UV(gv1 == gv2);             /* undef, undef */ /* XXX return 1? */
            /* XSRETURN_UV(1); */
        } else {
            XSRETURN_UV(0);                      /* glob, undef */
        }

void
xs_glob_id(GV * gv)
    PROTOTYPE:$
    CODE:
        XSRETURN_UV(PTR2UV(isGV(gv) ? GvGP(gv) : 0));

char *
xs_sig()
    PROTOTYPE:
    CODE:
        RETVAL = MYSUBS_INSTALLED;
    OUTPUT:
        RETVAL

void
xs_enter()
    PROTOTYPE:
    CODE:
        mysubs_enter();

void
xs_leave()
    PROTOTYPE:
    CODE:
        mysubs_leave();
