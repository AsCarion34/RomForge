using System.Collections.Generic;

namespace PBP.Core.AT3;

internal enum PartStatus
{
    Ok,
    Repeat
}

internal interface IBitStreamPartEncoder
{
    PartStatus Encode(EncodeCtx ctx, BitAllocHandler ba);
    void Dump(BitStreamWriter bs);
    void Reset();
}

internal sealed class BitAllocHandler
{
    private long _targetBits;
    private float _minLambda;
    private float _maxLambda;
    private float _curLambda;
    private float _lastLambda;

    internal bool NeedRepeat;
    internal int CurEncPos;
    internal int RepeatEncPos;

    public void Start(long targetBits, float minLambda, float maxLambda)
    {
        _targetBits = targetBits;
        _minLambda = minLambda;
        _maxLambda = maxLambda;
        _lastLambda = maxLambda;
    }

    public float Continue()
    {
        if (_maxLambda <= _minLambda)
            return _lastLambda;

        _curLambda = (_maxLambda + _minLambda) / 2.0f;
        RepeatEncPos = CurEncPos;
        return _curLambda;
    }

    public bool Submit(long gotBits)
    {
        if (_maxLambda <= _minLambda)
        {
            NeedRepeat = false;
        }
        else
        {
            if (gotBits < _targetBits)
            {
                _lastLambda = _curLambda;
                _maxLambda = _curLambda - 0.01f;
                NeedRepeat = true;
            }
            else if (gotBits > _targetBits)
            {
                _minLambda = _curLambda + 0.01f;
                NeedRepeat = true;
            }
            else
            {
                NeedRepeat = false;
            }
        }
        return !NeedRepeat;
    }
}

internal sealed class BitStreamEncoder
{
    private readonly List<IBitStreamPartEncoder> _parts;
    private readonly BitAllocHandler _ba = new();

    public BitStreamEncoder(List<IBitStreamPartEncoder> parts)
    {
        _parts = parts;
    }

    public void Do(EncodeCtx ctx, BitStreamWriter bs)
    {
        bool cont = false;
        do
        {
            for (_ba.CurEncPos = _ba.RepeatEncPos; _ba.CurEncPos < _parts.Count; _ba.CurEncPos++)
            {
                var status = _parts[_ba.CurEncPos].Encode(ctx, _ba);
                if (_ba.NeedRepeat)
                {
                    _ba.NeedRepeat = false;
                    cont = true;
                    break;
                }

                cont = false;

                if (status == PartStatus.Repeat)
                {
                    cont = true;
                    for (int i = 0; i < _ba.CurEncPos; i++)
                        _parts[i].Reset();
                    _ba.RepeatEncPos = 0;
                    break;
                }
            }
        } while (cont);

        foreach (var part in _parts)
            part.Dump(bs);

        _ba.RepeatEncPos = 0;
    }
}
