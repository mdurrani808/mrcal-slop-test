// Smoke-test the mrcal C library loaded from a pre-built tarball.
// Verifies that the shared library links and that basic API calls work.
#include <cstdio>
#include <cstring>
#include <mrcal/mrcal.h>

static int failures = 0;

static void check(bool ok, const char* msg)
{
    if (ok) {
        printf("OK:   %s\n", msg);
    } else {
        fprintf(stderr, "FAIL: %s\n", msg);
        ++failures;
    }
}

int main()
{
    printf("=== mrcal smoketest ===\n\n");

    // ------------------------------------------------------------------
    // 1. Lens model name round-trip
    // ------------------------------------------------------------------
    mrcal_lensmodel_t model;
    memset(&model, 0, sizeof(model));
    model.type = MRCAL_LENSMODEL_PINHOLE;

    const char* name = mrcal_lensmodel_name_unconfigured(&model);
    check(name != nullptr,                       "mrcal_lensmodel_name_unconfigured() != NULL");
    check(name && strstr(name, "PINHOLE") != nullptr,
                                                 "PINHOLE name contains 'PINHOLE'");
    if (name)
        printf("      name = \"%s\"\n", name);

    // ------------------------------------------------------------------
    // 2. Intrinsics parameter count for the PINHOLE model
    //    (fx, fy, cx, cy) -> 4 params
    // ------------------------------------------------------------------
    int nparams = mrcal_lensmodel_num_params(&model);
    check(nparams == 4, "mrcal_lensmodel_num_params(PINHOLE) == 4");
    printf("      nparams = %d\n", nparams);

    // ------------------------------------------------------------------
    // 3. OpenCV8 model (8 distortion coeffs + 4 = 12 total)
    // ------------------------------------------------------------------
    mrcal_lensmodel_t opencv8;
    memset(&opencv8, 0, sizeof(opencv8));
    opencv8.type = MRCAL_LENSMODEL_OPENCV8;

    const char* cv8name = mrcal_lensmodel_name_unconfigured(&opencv8);
    check(cv8name != nullptr,                    "mrcal_lensmodel_name_unconfigured(OPENCV8) != NULL");
    check(cv8name && strstr(cv8name, "OPENCV8") != nullptr,
                                                 "OPENCV8 name contains 'OPENCV8'");

    int cv8params = mrcal_lensmodel_num_params(&opencv8);
    check(cv8params == 12, "mrcal_lensmodel_num_params(OPENCV8) == 12");

    // ------------------------------------------------------------------
    // Result
    // ------------------------------------------------------------------
    printf("\n");
    if (failures > 0) {
        fprintf(stderr, "%d test(s) FAILED\n", failures);
        return 1;
    }
    printf("All smoketests PASSED\n");
    return 0;
}
