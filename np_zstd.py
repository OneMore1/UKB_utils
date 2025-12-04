# -*- coding: utf-8 -*-

import io

import numpy as np
import zstandard as zstd

_LEVEL = 8
_WRITE_CHECKSUM = True
_WRITE_CONTENT_SIZE = True

_cctx = zstd.ZstdCompressor(level=_LEVEL, write_checksum=_WRITE_CHECKSUM, write_content_size=_WRITE_CONTENT_SIZE)
_dctx = zstd.ZstdDecompressor()


def save(file, arr, allow_pickle=False) -> None:
    buf = io.BytesIO()
    np.save(buf, arr, allow_pickle=allow_pickle)

    with open(file, 'wb') as _f:
        _f.write(_cctx.compress(buf.getvalue()))


def savez(file, *args, allow_pickle=False, **kwargs) -> None:
    buf = io.BytesIO()
    np.savez(buf, *args, allow_pickle=allow_pickle, **kwargs)

    with open(file, 'wb') as _f:
        _f.write(_cctx.compress(buf.getvalue()))


def savez_compressed(file, *args, allow_pickle=False, **kwargs) -> None:
    savez(file, *args, allow_pickle=allow_pickle, **kwargs)


def load(file, allow_pickle=False, fix_imports=True, encoding='ASCII'):
    with open(file, 'rb') as _f:
        data = _f.read()

    buf = io.BytesIO(_dctx.decompress(data))
    return np.load(buf, allow_pickle=allow_pickle, fix_imports=fix_imports, encoding=encoding)
