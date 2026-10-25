using WiiU.Core.WUP.Models;

namespace WiiU.Core.WUP.Interfaces
{
    public interface IContentRule
    {
        string Pattern { get; set; }

        ContentDetails Details { get; set; }

        bool ContentPerMatch { get; set; }
    }
}