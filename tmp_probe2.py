import glob
common=set("的了是在不有和人我他你个上们这中大为来以就要可到说地对与也")
files=glob.glob("entry/src/main/ets/**/*.ets",recursive=True)+glob.glob("entry/src/main/ets/**/*.ts",recursive=True)
res=[]
for p in files:
    s=open(p,encoding="utf-8").read()
    cjk=[c for c in s if '\u4e00'<=c<='\u9fff']
    if len(cjk)<5: continue
    r=sum(1 for c in cjk if c in common)/len(cjk)
    res.append((r,p,len(cjk)))
res.sort()
bad=[x for x in res if x[0]<0.10]
good=[x for x in res if x[0]>=0.10]
print("SUSPECT",len(bad))
for r,p,n in bad[:200]: print(f"{r:.3f} {n:6d} {p}")
print("OK",len(good))
