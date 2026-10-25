namespace WiiU.Core.WUP.Interfaces
{
    public interface IHasData
    {
        byte[] GetAsData();

        int GetDataSize();
    }
}