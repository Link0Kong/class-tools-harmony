import glob,re
pat=re.compile(r"([\u4e00-\u9fff\ue000-\uf8ff])\?(?=[;,)\]}'\"]|$)")
gben={}
# map: 2-byte gbk prefix -> candidate chars
def cands(ch):
    b=ch.encode("gb18030")
    if len(b)!=2: return []
    out=[]
    for cp in range(0x4e00,0xa000):
        c=chr(cp)
        try: e=c.encode("utf-8")
        except: continue
        if len(e)==3 and e[0]==b[0] and e[1]==b[1]: out.append(c)
    return out
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    lines=open(p,encoding="utf-8").read().split("\n")
    for i,l in enumerate(lines):
        for m in pat.finditer(l):
            ch=m.group(1)
            cs=cands(ch)
            pre=l[:m.start()]
            # take literal prefix: last quote
            j=pre.rfind("'")
            lit=pre[j+1:] if j>=0 else pre[-12:]
            print(f"{p}:{i+1}|{lit}|{ch}|{''.join(cs)}|{l[m.end():m.end()+6]}")
