/*
    context marshalling massively pessimizes extensions built for threaded perls e.g. Cygwin.

    define PERL_CORE rather than PERL_NO_GET_CONTEXT (see perlguts) because PERL_GET_NO_CONTEXT still incurs the
    overhead of an extra function call for each interpreter variable
*/

#define PERL_CORE

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"
#include "ptable.h"

static PTABLE_t * OP_MAP = NULL;
static OP * (*old_ck_require)(pTHX_ OP * o) = NULL;
static OP * my_ck_require(pTHX_ OP * o);
static OP * my_require(pTHX);
static U32 SCOPE_DEPTH = 0;

static OP * my_ck_require(pTHX_ OP * o) {
    HV * table;
    SV ** svp;

    /* delegate to the original checker */
    o = CALL_FPTR(old_ck_require)(aTHX_ o);

    /* make sure it's still a require; the original checker may have turned it into an OP_ENTERSUB */
    if (!((o->op_type == OP_REQUIRE) || (o->op_type == OP_DOFILE))) {
        goto done;
    }

    if (o->op_type != OP_DOFILE) {
        if (o->op_flags & OPf_KIDS) { 
            SVOP * const kid = (SVOP*)cUNOPo->op_first;

            if (kid->op_type == OP_CONST) { /* weed out use VERSION */
                SV * const sv = kid->op_sv;

                if (SvNIOKp(sv)) { /* exclude use 5 and use 5.008 &c. */
                    goto done;
                }
#ifdef SvVOK
                if (SvVOK(sv)) { /* exclude use v5.008 and use 5.6.1 &c. */
                    goto done;
                }
#endif
                if (!SvPOKp(sv)) { /* err on the side of caution */
                    goto done;
                }
            }
        }
    }

    if ((table = GvHV(PL_hintgv)) && (svp = hv_fetch(table, "mysubs", 6, FALSE)) && *svp && SvOK(*svp)) {
        o->op_ppaddr = my_require;
        SvREFCNT_inc(*svp);
        PTABLE_store(OP_MAP, o, *svp);
        return o;
    }

    done:
    return o;
}

static OP * my_require(pTHX) {
    dSP;
    SV * sv, * bindings;
    OP * o;

    sv = TOPs;

    if (PL_op->op_type != OP_DOFILE) {
        if (SvNIOKp(sv)) { /* exclude use 5 and use 5.008 &c. */
            goto done;
        }
                
#ifdef SvVOK
        if (SvVOK(sv)) { /* exclude use v5.008 and use 5.6.1 &c. */
            goto done;
        }
#endif

        if (!SvPOKp(sv)) { /* err on the side of caution */
            goto done;
        }
    }

    /*
     * bindings is a reference to a hash whose keys are symbol names (e.g. 'main::foo') and whose values
     * are references to an array whose whose first member is the glob at the beginning
     * of the scope (before use mysubs) and whose second member is a reference to the lexical sub
     */

    bindings = (SV *)PTABLE_fetch(OP_MAP, PL_op);

    if (bindings && SvOK(bindings) && SvROK(bindings) && (SvTYPE(SvRV(bindings)) == SVt_PVHV)) {
        ENTER;
        SAVETMPS;

        PUSHMARK(SP);
        XPUSHs(bindings);
        PUTBACK;

        call_pv("mysubs::require_enter", G_DISCARD);

        FREETMPS;
        LEAVE;

        o = PL_ppaddr[cUNOP->op_type](aTHX);

        ENTER;
        SAVETMPS;

        SPAGAIN;

        PUSHMARK(SP);
        XPUSHs(bindings);
        PUTBACK;

        call_pv("mysubs::require_leave", G_DISCARD);

        FREETMPS;
        LEAVE;

        return o;
    }

    done:
    return PL_ppaddr[cUNOP->op_type](aTHX);
}

MODULE = mysubs                PACKAGE = mysubs                

BOOT:
OP_MAP = PTABLE_new(); if (!OP_MAP) Perl_croak(aTHX_ "Can't initialize op map");

void
END()
    PROTOTYPE:
    CODE:
        PTABLE_free(OP_MAP);
        OP_MAP = NULL;

void
_enter()
    PROTOTYPE:
    CODE:
        if (SCOPE_DEPTH > 0) {
            ++SCOPE_DEPTH;
        } else {
            SCOPE_DEPTH = 1;
            /*
             * capture the checker in scope when mysubs is used.
             * usually, this will be Perl_ck_require, though, in principle,
             * it could be a bespoke checker spliced in by another module.
             */
	    if (PL_check[OP_REQUIRE] != my_ck_require) {
		old_ck_require = PL_check[OP_REQUIRE];
		PL_check[OP_REQUIRE] = PL_check[OP_DOFILE] = my_ck_require;
	    }
        }

void
_leave()
    PROTOTYPE:
    CODE:
        if (SCOPE_DEPTH == 0) {
            Perl_warn(aTHX_ "mysubs: scope underflow");
        }

        if (SCOPE_DEPTH > 1) {
            --SCOPE_DEPTH;
        } else {
            SCOPE_DEPTH = 0;
            PL_check[OP_REQUIRE] = PL_check[OP_DOFILE] = old_ck_require;
        }
