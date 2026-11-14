/* Standalone regression test against the pinned VLC headers and backport. */
#include <assert.h>
#include "modules/packetizer/vp9_frame.h"
static unsigned pos;
static uint8_t data[32];
static void put(unsigned n, unsigned v) {
    for (unsigned i = n; i; i--, pos++)
        data[pos/8] |= ((v >> (i-1)) & 1) << (7-pos%8);
}
static void frame(unsigned profile) {
    memset(data, 0, sizeof(data)); pos = 0;
    put(2, 2); put(1, profile & 1); put(1, profile >> 1);
    put(1, 0); put(1, 0); put(1, 1); put(1, 0);
    put(24, 0x498342);
    if(profile >= 2) put(1, 0); /* 10 bit */
    put(3, 2); put(1, 0); /* BT709, limited range */
    put(16, 1919); put(16, 1079); put(1, 0); put(8, 0);
}
int main(void) {
    for(unsigned profile = 0; profile <= 2; profile += 2) {
        frame(profile);
        struct vp9_uncompressed_header h = {0};
        assert(vp9_parse_uncompressed_header(data, (pos+7)/8, &h));
        assert(h.profile == profile && h.bit_depth == (profile ? 10 : 8));
        assert(h.frame_width_minus1 == 1919 && h.frame_height_minus1 == 1079);
        assert(h.subsampling_xy == VP9_YUV_420 && h.show_frame);
        uint8_t dcr[VP9_DECODER_CONFIG_SIZE];
        assert(vp9_fill_decoder_config(&h, 40, CHROMA_LOCATION_LEFT, dcr));
        assert(dcr[0] == 1 && dcr[4] == profile && dcr[5] == 40);
        assert(dcr[6] == (h.bit_depth << 4));
        struct vp9_uncompressed_header copy = h;
        assert(vp9_configs_equals(&h, &copy));
        copy.bit_depth++;
        assert(!vp9_configs_equals(&h, &copy));
        h.subsampling_xy = VP9_YUV_440;
        assert(!vp9_fill_decoder_config(&h, 40, CHROMA_LOCATION_LEFT, dcr));
        data[1] = 0; /* corrupt sync code */
        assert(!vp9_parse_uncompressed_header(data, (pos+7)/8, &h));
        assert(!vp9_parse_uncompressed_header(data, 1, &h));
    }
    return 0;
}
