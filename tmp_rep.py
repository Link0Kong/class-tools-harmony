import glob,re
pat=re.compile(r"([\u4e00-\u9fff\ue000-\uf8ff])\?(?=[;,)\]}'\"]|$)")
head=open("head_corpus.txt",encoding="utf-8").read()
def cands(ch):
    b=ch.encode("gb18030",errors="replace")
    if len(b)!=2: return []
    out=[]
    for cp in range(0x2000,0xa000):
        c=chr(cp)
        e=c.encode("utf-8")
        if len(e)==3 and e[0]==b[0] and e[1]==b[1]: out.append(c)
    return out
rows=[]
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    lines=open(p,encoding="utf-8").read().split("\n")
    for i,l in enumerate(lines):
        for m in pat.finditer(l):
            ch=m.group(1); cs=cands(ch)
            pre=l[:m.start()]
            j=pre.rfind("'")
            lit=pre[j+1:] if j>=0 else pre
            # head suggestions
            sugg=[]
            if lit:
                idx=0
                while True:
                    k=head.find(lit,idx)
                    if k<0: break
                    nxt=head[k+len(lit):k+len(lit)+1]
                    if nxt in cs: sugg.append(nxt)
                    idx=k+1
            nxt=l[m.end():m.end()+8]
            rows.append((p,i+1,ch,"".join(cs[:40]),lit,nxt,"".join(sorted(set(sugg)))))
with open("damage_report.txt","w",encoding="utf-8") as f:
    for r in rows:
        f.write(f"{r[0]}:{r[1]}\tCH={r[2]}\tCAND={'|'.join(r[3])}\tPREFIX={r[4]}\tNEXT={r[5]}\tSUGG={r[6]}\n")
print(len(rows))
