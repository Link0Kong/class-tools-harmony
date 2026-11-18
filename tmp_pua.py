import glob,re,collections
bad=collections.Counter()
pua=re.compile(r"[\ue000-\uf8ff]")
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    s=open(p,encoding="utf-8").read()
    for c in pua.findall(s): bad[(p,c)]+=1
for (p,c),n in bad.items(): print("PUA",hex(ord(c)),p,n)
print("done")
