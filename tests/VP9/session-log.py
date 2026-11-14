#!/usr/bin/env python3
"""Exercise the exact patched diagnostic with mocked VideoToolbox/CF calls.
This tests failure semantics, not hardware or Apple framework integration.
"""
import pathlib, subprocess, sys, tempfile
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index('static void LogVP9HardwareSession(')
end = source.index('static int StartVideoToolbox(', start)
function = source[start:end].replace('__builtin_available(macOS 10.9, iOS 8.0, tvOS 10.2, *)', 'available')
harness = r'''
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
typedef int OSStatus;
typedef struct { int type; int value; } Value;
typedef Value *CFTypeRef;
typedef Value *CFBooleanRef;
typedef struct { void *session; } decoder_sys_t;
typedef struct { int i_codec; } format;
typedef struct { decoder_sys_t *p_sys; format *fmt_in; } decoder_t;
#define VLC_CODEC_VP9 9
#define noErr 0
#define kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder 0
#define kCFAllocatorDefault 0
static int available = 1, status, calls, releases;
static Value *result;
static char message[200];
static OSStatus VTSessionCopyProperty(void *s,int k,int a,CFTypeRef *v) { calls++; *v=result;return status; }
static int CFGetTypeID(CFTypeRef v) { return v->type; }
static int CFBooleanGetTypeID(void) { return 1; }
static int CFBooleanGetValue(CFBooleanRef v) { return v->value; }
static void CFRelease(CFTypeRef v) { assert(v);releases++; }
static void msg_Info(decoder_t *d, const char *fmt, ...) {
 va_list args;va_start(args,fmt);vsnprintf(message,sizeof(message),fmt,args);va_end(args);
}
'''
tests = r'''
static void check(decoder_t *d, int st, Value *v, const char *expected) {
 status=st;result=v;calls=releases=0;message[0]=0;
 LogVP9HardwareSession(d);
 assert(calls==1);assert(releases==(v!=NULL));assert(strstr(message,expected));
}
int main(void) {
 decoder_sys_t sys={0};format fmt={VLC_CODEC_VP9};decoder_t d={&sys,&fmt};
 Value yes={1,1},no={1,0},wrong={2,1};
 check(&d,0,&yes,"hardware=yes status=0");
 check(&d,0,&no,"hardware=no status=0");
 check(&d,-12900,NULL,"hardware=unknown status=-12900");
 check(&d,-12900,&yes,"hardware=unknown status=-12900");
 check(&d,0,NULL,"hardware=unknown status=0");
 check(&d,0,&wrong,"hardware=unknown status=0");
 available=0;calls=0;LogVP9HardwareSession(&d);
 assert(calls==0);assert(strstr(message,"hardware=unknown"));
 available=1;fmt.i_codec=1;message[0]=0;LogVP9HardwareSession(&d);
 assert(calls==0 && message[0]==0);
}
'''
with tempfile.TemporaryDirectory() as tmp:
    path=pathlib.Path(tmp);(path/'test.c').write_text(harness+function+tests)
    subprocess.run(['cc','-std=c11',str(path/'test.c'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test')],check=True)
print('PASS: session diagnostic yes/no/unknown, API unavailable, wrong type, release and non-VP9')
