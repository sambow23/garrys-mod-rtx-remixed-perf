// This code belongs to https://github.com/devonium/EGSM sorry for stealing it right now :(
// Quickly thrown in here for now just to see if this would work.
// hopefully we either get permission to use this or we can replace it with our own code.

#include "e_utils.h"
#include <Windows.h>
#include <scanning/symbolfinder.hpp>
#include <detouring/hook.hpp>
#include <tier0/dbg.h>

bool GetLibraryInfo(const void* handle, DynLibInfo& lib)
{
	if (handle == nullptr)
		return false;

#if defined ARCHITECTURE_X86

	const WORD IMAGE_FILE_MACHINE = IMAGE_FILE_MACHINE_I386;

#elif defined ARCHITECTURE_X86_64

	const WORD IMAGE_FILE_MACHINE = IMAGE_FILE_MACHINE_AMD64;

#endif

	MEMORY_BASIC_INFORMATION info;
	if (VirtualQuery(handle, &info, sizeof(info)) == FALSE)
		return false;

	uintptr_t baseAddr = reinterpret_cast<uintptr_t>(info.AllocationBase);

	IMAGE_DOS_HEADER* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(baseAddr);
	IMAGE_NT_HEADERS* pe = reinterpret_cast<IMAGE_NT_HEADERS*>(baseAddr + dos->e_lfanew);
	IMAGE_FILE_HEADER* file = &pe->FileHeader;
	IMAGE_OPTIONAL_HEADER* opt = &pe->OptionalHeader;

	if (dos->e_magic != IMAGE_DOS_SIGNATURE || pe->Signature != IMAGE_NT_SIGNATURE || opt->Magic != IMAGE_NT_OPTIONAL_HDR_MAGIC)
		return false;

	if (file->Machine != IMAGE_FILE_MACHINE)
		return false;

	if ((file->Characteristics & IMAGE_FILE_DLL) == 0)
		return false;

	lib.memorySize = opt->SizeOfImage;
	lib.baseAddress = reinterpret_cast<void*>(baseAddr);
	return true;
}

void* ScanSign(const void* handle, const char* sig, size_t len, const void* start)
{
	DynLibInfo lib;
	memset(&lib, 0, sizeof(DynLibInfo));
	if (!GetLibraryInfo(handle, lib))
		return nullptr;

	uint8_t* ptr = reinterpret_cast<uint8_t*>(start > lib.baseAddress ? const_cast<void*>(start) : lib.baseAddress);
	uint8_t* end = reinterpret_cast<uint8_t*>(lib.baseAddress) + lib.memorySize - len;
	bool found = true;
	while (ptr < end)
	{
		uint8_t* tmp = ptr;
		for (size_t i = 0; i < len; ++i)
		{
			if (sig[i] == ' ') { continue; }
			if (sig[i] == '?') { tmp++; continue; }

			if (tmp[0] != strtoul(&sig[i], NULL, 16))
			{
				found = false;
				break;
			}
			i++;
			tmp++;
		}

		if (found)
			return ptr;

		++ptr;
		found = true;
	}

	return nullptr;
}

#ifdef _WIN64
// Find the D3D9 device used by Source engine
void* FindD3D9Device() {
    auto shaderapidx = GetModuleHandle("shaderapidx9.dll");
    if (!shaderapidx) {
        Warning("[gmRTX - Binary Module] Failed to get shaderapidx9.dll module\n");
        return nullptr;
    }

    Msg("[gmRTX - Binary Module] shaderapidx9.dll module: %p\n", shaderapidx);

    static const char sign[] = "BA E1 0D 74 5E 48 89 1D ?? ?? ?? ??";
    auto ptr = ScanSign(shaderapidx, sign, sizeof(sign) - 1);
    if (!ptr) {
        Warning("[gmRTX - Binary Module] Failed to find D3D9Device signature\n");
        return nullptr;
    }

    auto offset = ((uint32_t*)ptr)[2];
    auto device = *(void**)((char*)ptr + offset + 12);
    if (!device) {
        Warning("[gmRTX - Binary Module] D3D9Device pointer is null\n");
        return nullptr;
    }

    return device;
}
#else
// 32-bit version not implemented yet
void* FindD3D9Device() {
    Warning("[gmRTX - Binary Module] FindD3D9Device not implemented for 32-bit\n");
    return nullptr;
}
#endif