#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "hook_op_check.h"
#include "hook_op_annotation.h"

#include "stdlib.h" /* for getenv */
#include "string.h" /* for strchr */
#define NDEBUG
#include "assert.h"

#define MYSUBS_INSTALLED "mysubs"

#define MYSUBS_ENABLED(table, svp)                                                  \
    ((PL_hints & 0x20000) &&                                                        \
    (table = GvHV(PL_hintgv)) &&                                                    \
    (svp = hv_fetch(table, MYSUBS_INSTALLED, strlen(MYSUBS_INSTALLED), FALSE)) &&   \
    *svp &&                                                                         \
    SvOK(*svp) &&                                                                   \
    SvROK(*svp) &&                                                                  \
    SvRV(*svp) &&                                                                   \
    SvTYPE(SvRV(*svp)) == SVt_PVHV)

#define MYSUBS_REDO 1

STATIC OP * mysubs_check_prototype(pTHX_ OP * o, void * user_data);
STATIC OP * mysubs_prototype(pTHX);
STATIC void mysubs_enter();
STATIC void mysubs_hv_free(pTHX_ void * data);
STATIC void mysubs_leave();

STATIC hook_op_check_id mysubs_check_prototype_id = 0;
STATIC OPAnnotationGroup MYSUBS_ANNOTATIONS = NULL;
STATIC U32 MYSUBS_COMPILING = 0;
STATIC U32 MYSUBS_DEBUG = 0;

STATIC void mysubs_hv_free(pTHX_ void * data) {
    HV *hv = (HV *)data;
    hv_clear(hv);
    hv_undef(hv);
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
        (void)op_annotation_new(MYSUBS_ANNOTATIONS, o, SvRV(*svp), mysubs_hv_free);
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
        SV * fqname = NULL;
        SV ** svp;
        U32 cleanup = 1;
        HV * installed = (HV *)annotation->data;
        STRLEN len;
        const char * s = SvPV_const(sv, len);

        assert(installed);
        assert(SvTYPE(installed) == SVt_PVHV);
        assert(s);

        if (strchr(s, '\'')) {
            STRLEN i;
            /* there are more efficient ways to do this, but this works without tears in older perls */
            fqname = newSVpvn("", 0);
            assert(fqname);
            assert(SvOK(fqname));
            assert(SvPOK(fqname));

            for (i = 0; i < len; ++i) {
                if (s[i] == '\'') {
                    sv_catpvs(fqname, "::");
                } else {
                    sv_catpvn(fqname, s + i, 1);
                }
            }
        } else if (strchr(s, ':')) {
            fqname = sv;
            cleanup = 0;
        } else if (MYSUBS_COMPILING) { /* compile-time */
            fqname = newSVpvf("%s::%s", HvNAME(PL_curstash ? PL_curstash : PL_defstash), s);
        } else { /* runtime */
            fqname = newSVpvf("%s::%s", CopSTASHPV(PL_curcop) , s);
        }

        assert(fqname);
        assert(SvOK(fqname));
        assert(SvPOK(fqname));

        if (MYSUBS_DEBUG) {
            warn("mysubs: looking up prototype: %s", SvPV_nolen_const(fqname));
        }

        svp = hv_fetch(installed, SvPV_nolen_const(fqname), SvCUR(fqname), 0);

        if (cleanup) {
            SvREFCNT_dec(fqname);
        }

        if (svp && *svp && SvOK(*svp) && SvROK(*svp) && (SvTYPE(SvRV(*svp)) == SVt_PVAV)) {
            AV * pair;

            pair = (AV *)(SvRV(*svp));
            svp = av_fetch(pair, MYSUBS_REDO, 0); /* $installed->{$fqname}->[REDO] */

            if (svp && *svp && isGV(*svp)) {
                GV * gv = (GV *)*svp;
                if (GvCV(gv)) {
                    if (MYSUBS_DEBUG) {
                        warn("mysubs: found prototype");
                    }
                    SETs((SV*)GvCV(gv));
                }
            }
        }
    }

    return CALL_FPTR(annotation->op_ppaddr)(aTHX);
}

STATIC void mysubs_enter() {
    if (MYSUBS_COMPILING != 0) {
        croak("mysubs: scope overflow");
    } else {
        MYSUBS_COMPILING = 1;
        mysubs_check_prototype_id = hook_op_check(OP_PROTOTYPE, mysubs_check_prototype, NULL);
    }
}

STATIC void mysubs_leave() {
    if (MYSUBS_COMPILING != 1) {
        croak("mysubs: scope underflow");
    } else {
        MYSUBS_COMPILING = 0;
        hook_op_check_remove(OP_PROTOTYPE, mysubs_check_prototype_id);
    }
}

MODULE = mysubs                PACKAGE = mysubs                

BOOT:
    if (getenv("MYSUBS_DEBUG")) {
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
        assert(SvOK(sv));
        assert(SvROK(sv));
        assert(SvRV(sv));
        assert(SvTYPE(SvRV(sv)) == SVt_PVHV);
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
