#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

MODULE = mysubs                PACKAGE = mysubs                

SV *
delete_sub(SV * sv)
    PROTOTYPE:$
    PREINIT:
        const GV * gv;
        const CV * deleted;
        const char * name;
    CODE:
        name = SvPV_nolen_const(sv);
        gv = Perl_gv_fetchpv(aTHX_ name, 0, SVt_PVCV);

        if (gv && GvCV(gv)) {
            deleted = GvCV(gv);
            GvCV(gv) = NULL;
            RETVAL = newRV_noinc((SV *)deleted);
        } else {
            XSRETURN_UNDEF;
        }
    OUTPUT:
        RETVAL
