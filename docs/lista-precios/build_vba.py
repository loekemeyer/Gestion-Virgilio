# Reemplaza el código de un módulo VBA dentro de un vbaProject.bin (sin abrir Excel).
# Uso: python build_vba.py <vbaProject.bin original> <modulo.bas con token> <salida.bin>
# Fuerza a Excel a recompilar (_VBA_PROJECT versión 0xFFFF, sin __SRP_*). v32.10, 16/10.
# Después: reemplazar sólo xl/vbaProject.bin dentro del .xlsm (el resto del zip, igual).
import sys, struct, olefile
from oletools.olevba import decompress_stream

# ---------- MS-OVBA compresión (2.4.1.3) ----------
def compress(data: bytes) -> bytes:
    out = bytearray(b'\x01')
    pos = 0
    while pos < len(data):
        chunk = data[pos:pos+4096]; pos += 4096
        body = bytearray(); i = 0
        while i < len(chunk):
            flag_idx = len(body); body.append(0); flags = 0
            for bit in range(8):
                if i >= len(chunk): break
                # bit count según posición en el chunk
                d = i
                bc = max((d-1).bit_length(), 4) if d > 0 else 4
                lmask = 0xFFFF >> bc; maxlen = lmask + 3
                best_len = 0; best_off = 0
                start = max(0, i - (1 << bc))
                if i > 0:
                    for cand in range(i-1, start-1, -1):
                        l = 0
                        while i+l < len(chunk) and l < maxlen and chunk[cand+l] == chunk[i+l]:
                            l += 1
                        if l > best_len: best_len, best_off = l, i-cand
                        if best_len == maxlen: break
                if best_len >= 3:
                    tok = ((best_off-1) << (16-bc)) | (best_len-3)
                    body += struct.pack('<H', tok); flags |= (1 << bit); i += best_len
                else:
                    body.append(chunk[i]); i += 1
            body[flag_idx] = flags
        if len(body) > 4096:  # no conviene: chunk sin comprimir (requiere 4096 exactos)
            assert len(chunk) == 4096
            hdr = (4096-1) | (0b011 << 12)  # flag 0
            out += struct.pack('<H', hdr) + chunk
        else:
            hdr = (len(body)+2-3) | (0b011 << 12) | 0x8000
            out += struct.pack('<H', hdr) + body
    return bytes(out)

# ---------- CFB v3 writer ----------
FREE, ENDC, FATS = 0xFFFFFFFF, 0xFFFFFFFE, 0xFFFFFFFD
NOS = 0xFFFFFFFF
def cfb_key(n): return (len(n), n.upper())

def write_cfb(path, root_clsid, tree):
    # tree: dict name -> bytes (stream) or ('stg', clsid, dict)
    entries = []  # dicts
    def add(name, typ, clsid=b'\0'*16, data=None):
        entries.append(dict(name=name, typ=typ, clsid=clsid, data=data, left=NOS, right=NOS, child=NOS, start=ENDC, size=0))
        return len(entries)-1
    root = add('Root Entry', 5, root_clsid)
    def build(parent, d):
        ids = []
        for name, v in d.items():
            if isinstance(v, tuple):
                sid = add(name, 1, v[1]); build(sid, v[2])
            else:
                sid = add(name, 2, data=v)
            ids.append(sid)
        ids.sort(key=lambda s: cfb_key(entries[s]['name']))
        def bal(lst):
            if not lst: return NOS
            m = len(lst)//2
            entries[lst[m]]['left'] = bal(lst[:m]); entries[lst[m]]['right'] = bal(lst[m+1:])
            return lst[m]
        entries[parent]['child'] = bal(ids)
    build(root, tree)
    # mini stream
    mini = bytearray(); minifat = []
    big = []
    for e in entries:
        if e['typ'] != 2: continue
        e['size'] = len(e['data'])
        if e['size'] == 0: e['start'] = ENDC; continue
        if e['size'] < 4096:
            n = (e['size']+63)//64; s = len(mini)//64
            e['start'] = s
            mini += e['data'] + b'\0'*(n*64-e['size'])
            minifat += [s+k+1 for k in range(n-1)] + [ENDC]
        else:
            big.append(e)
    secs = []  # list of (kind, bytes) per sector chain
    fat = []
    def alloc(data, kind=None):
        n = (len(data)+511)//512
        s = len(fat)
        for k in range(n): fat.append(s+k+1 if k < n-1 else ENDC)
        secs.append(bytes(data) + b'\0'*(n*512-len(data)))
        return s
    for e in big: e['start'] = alloc(e['data'])
    if mini:
        entries[root]['start'] = alloc(mini); entries[root]['size'] = len(mini)
    mfat_bytes = b''.join(struct.pack('<I', x) for x in minifat)
    mfat_start = alloc(mfat_bytes) if minifat else ENDC
    mfat_n = (len(mfat_bytes)+511)//512
    ndir = (len(entries)+3)//4
    dir_start_placeholder = len(fat)
    # dir data built after (start sectors known); reserve
    for k in range(ndir): fat.append(dir_start_placeholder+k+1 if k < ndir-1 else ENDC)
    # FAT sectors
    nfat = 1
    while True:
        total = len(fat) + nfat
        if (total+127)//128 <= nfat: break
        nfat += 1
    assert nfat <= 109
    fat_start = len(fat)
    for k in range(nfat): fat.append(FATS)
    while len(fat) % 128: fat.append(FREE)
    fat_bytes = b''.join(struct.pack('<I', x) for x in fat)
    def dirent(e):
        nm = e['name'].encode('utf-16-le') + b'\0\0'
        assert len(nm) <= 64
        b = nm + b'\0'*(64-len(nm))
        b += struct.pack('<HBB', len(nm), e['typ'], 1)
        b += struct.pack('<III', e['left'], e['right'], e['child'])
        b += e['clsid'] + b'\0'*4 + b'\0'*16
        b += struct.pack('<II', e['start'] if e['typ'] != 1 else 0, 0) if False else b''
        st = e['start'] if e['typ'] in (2, 5) else 0
        sz = e['size'] if e['typ'] in (2, 5) else 0
        if e['typ'] == 5 and not mini: st = ENDC
        b += struct.pack('<IQ', st, sz)
        assert len(b) == 128
        return b
    dirb = b''.join(dirent(e) for e in entries)
    empty = b'\0'*64 + struct.pack('<HBB', 0, 0, 0) + struct.pack('<III', NOS, NOS, NOS) + b'\0'*36 + struct.pack('<IQ', 0, 0)
    while len(dirb) < ndir*512: dirb += empty
    hdr = bytearray(512)
    hdr[0:8] = bytes.fromhex('D0CF11E0A1B11AE1')
    struct.pack_into('<HHHHH', hdr, 24, 0x3E, 3, 0xFFFE, 9, 6)
    struct.pack_into('<IIIIIIII', hdr, 40, 0, nfat, dir_start_placeholder, 0, 4096, mfat_start, mfat_n if minifat else 0, ENDC)
    struct.pack_into('<I', hdr, 72, 0)  # num DIFAT sectors
    for k in range(109):
        struct.pack_into('<I', hdr, 76+4*k, fat_start+k if k < nfat else FREE)
    with open(path, 'wb') as f:
        f.write(hdr)
        for s in secs: f.write(s)
        f.write(dirb)
        f.write(fat_bytes)

# ---------- armar el proyecto ----------
src_bin, bas, out = sys.argv[1], sys.argv[2], sys.argv[3]
MOD = 'Módulo1'
o = olefile.OleFileIO(src_bin)
dirc = o.openstream('VBA/dir').read()
d = bytearray(decompress_stream(bytearray(dirc)))
k = d.find(MOD.encode('cp1252')); j = d.find(b'\x31\x00\x04\x00\x00\x00', k)
assert k > 0 and j > k
struct.pack_into('<I', d, j+6, 0)
text = open(bas, encoding='utf-8').read().replace('\r\n', '\n').split('\n')
assert text[0].startswith('Attribute VB_Name')
text[0] = 'Attribute VB_Name = "%s"' % MOD
source = '\r\n'.join(text).rstrip('\r\n') + '\r\n'
srcb = source.encode('cp1252')
# validar ida y vuelta de la compresión
assert bytes(decompress_stream(bytearray(compress(srcb)))) == srcb
assert bytes(decompress_stream(bytearray(compress(bytes(d))))) == bytes(d)

def tree_of(prefix):
    res = {}
    for e in o.listdir(streams=True, storages=True):
        pass
    return res
vba = {}
for e in o.listdir(streams=True, storages=False):
    if len(e) == 2 and e[0] == 'VBA':
        n = e[1]
        if n.startswith('__SRP_'): continue
        data = o.openstream('/'.join(e)).read()
        if n == 'dir': data = compress(bytes(d))
        elif n == MOD: data = compress(srcb)
        elif n == '_VBA_PROJECT': data = b'\xCC\x61\xFF\xFF\x00\x00\x00'
        vba[n] = data
top = {}
for e in o.listdir(streams=True, storages=False):
    if len(e) == 1: top[e[0]] = o.openstream(e[0]).read()
top['VBA'] = ('stg', o.getclsid('VBA') and bytes.fromhex(o.getclsid('VBA').replace('-', '')) if o.getclsid('VBA') else b'\0'*16, vba)
rc = o.root.clsid
root_clsid = b'\0'*16 if not rc else olefile.olefile._clsid if False else b'\0'*16
write_cfb(out, root_clsid, top)
print('ok', out, len(srcb), 'bytes de fuente')
