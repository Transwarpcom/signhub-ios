#ifndef SignHub_Bridging_Header_h
#define SignHub_Bridging_Header_h

#import <zlib.h>
#import <Security/Security.h>

// zsign 的入口（把原 main 改名后导出）
int zsign_run_main_c(int argc, char **argv);

#endif
