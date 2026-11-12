using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
if (string.IsNullOrEmpty(home)) home = "/home";

var sdkBase = args.Length > 0 ? args[0] : Path.Combine(home, ".dotnet", "sdk");

if (!Directory.Exists(sdkBase))
{
    Console.Error.WriteLine($"SDK directory not found: {sdkBase}");
    return 1;
}

var anyPatched = false;

foreach (var dir in Directory.GetDirectories(sdkBase))
{
    var dll = Path.Combine(dir, "Microsoft.TestPlatform.CoreUtilities.dll");
    if (File.Exists(dll) && PatchDll(dll))
        anyPatched = true;
}

if (!anyPatched)
    Console.Error.WriteLine("No DLLs were patched");

return anyPatched ? 0 : 1;

static bool PatchDll(string path)
{
    Console.WriteLine($"Checking: {path}");

    try
    {
        // IL patch: tiny method header (2-byte body) + ldc.i4.1 + ret
        // Tiny header: (codeSize << 2) | 0x02 = (2 << 2) | 0x02 = 0x0A
        byte[] ilPatch = [0x0A, 0x17, 0x2A];

        int methodFileOffset;

        using (var fs = File.OpenRead(path))
        using (var peReader = new PEReader(fs))
        {
            var mdReader = peReader.GetMetadataReader();
            int methodRva = FindMethodRva(mdReader);

            if (methodRva == 0)
            {
                Console.WriteLine("  IsValidArchitectureMuxer not found, skipping");
                return false;
            }

            Console.WriteLine($"  Method RVA: 0x{methodRva:X}");
            methodFileOffset = RvaToFileOffset(peReader, methodRva);
            Console.WriteLine($"  File offset: 0x{methodFileOffset:X}");
        }

        // Check if already patched
        var currentBytes = new byte[3];
        using (var fs = File.OpenRead(path))
        {
            fs.Seek(methodFileOffset, SeekOrigin.Begin);
            fs.ReadExactly(currentBytes);
        }

        if (currentBytes.AsSpan().SequenceEqual(ilPatch))
        {
            Console.WriteLine("  Already patched");
            return true;
        }

        // Backup original
        var backup = path + ".orig";
        if (!File.Exists(backup))
        {
            File.Copy(path, backup);
            Console.WriteLine($"  Backup: {backup}");
        }

        // Patch the method body: replace IsValidArchitectureMuxer with "return true".
        // The wrapper also sets DOTNET_ReadyToRun=0 to force JIT from this patched IL
        // instead of using the pre-compiled R2R native code.
        using (var fs = File.Open(path, FileMode.Open, FileAccess.Write))
        {
            fs.Seek(methodFileOffset, SeekOrigin.Begin);
            fs.Write(ilPatch);
        }

        Console.WriteLine("  Patched!");
        return true;
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"  Error: {ex.Message}");
        return false;
    }
}

static int FindMethodRva(MetadataReader mdReader)
{
    foreach (var typeHandle in mdReader.TypeDefinitions)
    {
        var typeDef = mdReader.GetTypeDefinition(typeHandle);
        if (mdReader.GetString(typeDef.Name) != "DotnetHostHelper")
            continue;

        foreach (var methodHandle in typeDef.GetMethods())
        {
            var methodDef = mdReader.GetMethodDefinition(methodHandle);
            if (mdReader.GetString(methodDef.Name) == "IsValidArchitectureMuxer")
                return methodDef.RelativeVirtualAddress;
        }
    }
    return 0;
}

static int RvaToFileOffset(PEReader peReader, int rva)
{
    foreach (var section in peReader.PEHeaders.SectionHeaders)
    {
        if (rva >= section.VirtualAddress && rva < section.VirtualAddress + section.SizeOfRawData)
            return rva - section.VirtualAddress + section.PointerToRawData;
    }
    throw new InvalidOperationException($"No PE section contains RVA 0x{rva:X}");
}
