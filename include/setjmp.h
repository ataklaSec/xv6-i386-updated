#ifndef _UCC_SETJMP_H
#define _UCC_SETJMP_H

typedef int jmp_buf[6];
int setjmp(jmp_buf);
void longjmp(jmp_buf, int);

#endif  /* setjmp.h */
