import glob,re
pat=re.compile(r"[\u4e00-\u9fff\ue000-\uf8ff]\?(?=[;,)\]}'\"]|$)")
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    lines=open(p,encoding="utf-8").read().split("\n")
    hits=[]
    for i,l in enumerate(lines):
        if pat.search(l):
            hits.append((i+1,l))
    if hits:
        print("=====",p)
        for i,l in hits:
            print(f"  {i}: {l.strip()}".encode("unicode_escape").decode())
