namespace WiiGC.Core.Models;

internal sealed record WiiPartitionSpec(long ContainerOffset, long DataStart, long DataSize, byte[] Key);