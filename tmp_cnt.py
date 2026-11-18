import glob,re
pat=re.compile(r"[\u4e00-\u9fff\ue000-\uf8ff]\?(?=[;,)\]}'\"]|$)")
tot=0
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    s=open(p,encoding="utf-8").read()
    m=pat.findall(s)
    if m:
        print(f"{len(m):4d} {p}")
        tot+=len(m)
print("TOTAL",tot)
