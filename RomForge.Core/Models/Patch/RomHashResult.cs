namespace RomForge.Core.Models.Patch;

public readonly record struct RomHashResult(string Crc32, string Md5, string Sha1, long Length);