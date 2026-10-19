namespace PickPack.Disk.Models
{
    public class ProgressEventArgs : EventArgs
    {
        public int Percent { get; set; }

        public string ?Message1 { get; set; }

        public string ?Message2 { get; set; }
    }
}