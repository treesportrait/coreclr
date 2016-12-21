// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.
// See the LICENSE file in the project root for more information.

.intel_syntax noprefix
#include "unixasmmacros.inc"
#include "asmconstants.h"

//
// eax = UMEntryThunk*
//
NESTED_ENTRY TheUMEntryPrestub, _TEXT, UnhandledExceptionHandlerUnix
    // Preserve argument registers
    push    ecx
    push    edx

    push    eax  // UMEntryThunk*
    call    C_FUNC(TheUMEntryPrestubWorker)
    pop     edx
    // eax = PCODE

    // Restore argument registers
    pop     edx
    pop     ecx

    jmp     eax     // Tail Jmp
NESTED_END TheUMEntryPrestub, _TEXT

//
// eax: UMEntryThunk*
//
NESTED_ENTRY UMThunkStub, _TEXT, UnhandledExceptionHandlerUnix

#define UMThunkStub_SAVEDREG                (3*4)   // ebx, esi, edi
#define UMThunkStub_LOCALVARS               (2*4)   // UMEntryThunk*, Thread*
#define UMThunkStub_INT_ARG_SPILL           (2*4)   // for save ecx, edx
#define UMThunkStub_UMENTRYTHUNK_OFFSET     (UMThunkStub_SAVEDREG+4)
#define UMThunkStub_THREAD_OFFSET           (UMThunkStub_UMENTRYTHUNK_OFFSET+4)
#define UMThunkStub_INT_ARG_OFFSET          (UMThunkStub_THREAD_OFFSET+4)
#define UMThunkStub_FIXEDALLOCSIZE          (UMThunkStub_LOCALVARS+UMThunkStub_INT_ARG_SPILL)

// return address                           <-- entry ESP
// saved ebp                                <-- EBP
// saved ebx
// saved esi
// saved edi
// UMEntryThunk*
// Thread*
// save ecx
// save edx
// {optional stack args passed to callee}   <-- new esp

    PROLOG_BEG
    PROLOG_PUSH ebx
    PROLOG_PUSH esi
    PROLOG_PUSH edi
    PROLOG_END
    sub     esp, UMThunkStub_FIXEDALLOCSIZE

    mov     dword ptr [ebp - UMThunkStub_INT_ARG_OFFSET], ecx
    mov     dword ptr [ebp - UMThunkStub_INT_ARG_OFFSET - 0x04], edx

    mov     dword ptr [ebp - UMThunkStub_UMENTRYTHUNK_OFFSET], eax

    call    C_FUNC(GetThread)
    test    eax, eax
    jz      LOCAL_LABEL(DoThreadSetup)

LOCAL_LABEL(HaveThread):

    mov     dword ptr [ebp - UMThunkStub_THREAD_OFFSET], eax

    // FailFast if a native callable method is invoked via ldftn and calli.
    cmp     dword ptr [eax + Thread_m_fPreemptiveGCDisabled], 1
    jz      LOCAL_LABEL(InvalidTransition)

    // disable preemptive GC
    mov     dword ptr [eax + Thread_m_fPreemptiveGCDisabled], 1

    // catch returning thread here if a GC is in progress
    PREPARE_EXTERNAL_VAR g_TrapReturningThreads, eax
    cmp     eax, 0
    jnz     LOCAL_LABEL(DoTrapReturningThreadsTHROW)

LOCAL_LABEL(InCooperativeMode):

#if _DEBUG
    mov     eax, dword ptr [ebp - UMThunkStub_THREAD_OFFSET]
    mov     eax, dword ptr [eax + Thread__m_pDomain]
    mov     esi, dword ptr [eax + AppDomain__m_dwId]

    mov     eax, dword ptr [ebp - UMThunkStub_UMENTRYTHUNK_OFFSET]
    mov     edi, dword ptr [eax + UMEntryThunk__m_dwDomainId]

    cmp     esi, edi
    jne     LOCAL_LABEL(WrongAppDomain)
#endif

    mov     eax, dword ptr [ebp - UMThunkStub_UMENTRYTHUNK_OFFSET]
    mov     ebx, dword ptr [eax + UMEntryThunk__m_pUMThunkMarshInfo]
    mov     eax, dword ptr [ebx + UMThunkMarshInfo__m_cbActualArgSize]
    test    eax, eax
    jnz     LOCAL_LABEL(UMThunkStub_CopyStackArgs)

LOCAL_LABEL(UMThunkStub_ArgumentsSetup):

    mov     ecx, dword ptr [ebp - UMThunkStub_INT_ARG_OFFSET]
    mov     edx, dword ptr [ebp - UMThunkStub_INT_ARG_OFFSET - 0x04]

    mov     eax, dword ptr [ebp - UMThunkStub_UMENTRYTHUNK_OFFSET]
    mov     ebx, dword ptr [eax + UMEntryThunk__m_pUMThunkMarshInfo]
    mov     ebx, dword ptr [ebx + UMThunkMarshInfo__m_pILStub]

    call    ebx

LOCAL_LABEL(PostCall):

    mov     ebx, dword ptr [ebp - UMThunkStub_THREAD_OFFSET]
    mov     dword ptr [ebx + Thread_m_fPreemptiveGCDisabled], 0

    lea     esp, [ebp - UMThunkStub_SAVEDREG]  // deallocate arguments
    EPILOG_BEG
    EPILOG_POP edi
    EPILOG_POP esi
    EPILOG_POP ebx
    EPILOG_END
    ret

LOCAL_LABEL(DoThreadSetup):

    call    C_FUNC(CreateThreadBlockThrow)
    jmp     LOCAL_LABEL(HaveThread)

LOCAL_LABEL(InvalidTransition):

    //No arguments to setup , ReversePInvokeBadTransition will failfast
    call    C_FUNC(ReversePInvokeBadTransition)

LOCAL_LABEL(DoTrapReturningThreadsTHROW):

    // extern "C" VOID STDCALL UMThunkStubRareDisableWorker(Thread *pThread, UMEntryThunk *pUMEntryThunk)
    mov     eax, dword ptr [ebp - UMThunkStub_UMENTRYTHUNK_OFFSET]
    push    eax
    mov     eax, dword ptr [ebp - UMThunkStub_THREAD_OFFSET]
    push    eax
    call    C_FUNC(UMThunkStubRareDisableWorker)

    jmp     LOCAL_LABEL(InCooperativeMode)

LOCAL_LABEL(UMThunkStub_CopyStackArgs):

    // eax = m_cbActualArgSize
    sub     esp, eax
    and     esp, -16    // align with 16 byte
    lea     esi, [ebp + 0x08]
    lea     edi, [esp]

LOCAL_LABEL(CopyLoop):

    // eax = number of bytes
    // esi = src
    // edi = dest
    // edx = sratch

    add     eax, -4
    mov     edx, dword ptr [esi + eax]
    mov     dword ptr [edi + eax], edx
    jnz     LOCAL_LABEL(CopyLoop)

    jmp     LOCAL_LABEL(UMThunkStub_ArgumentsSetup)

#if _DEBUG
LOCAL_LABEL(WrongAppDomain):
    int3
#endif

NESTED_END UMThunkStub, _TEXT