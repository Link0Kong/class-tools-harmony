import glob
common=set("的了是在不有和人我他你个上们这中大为来以就要可到说地对与也把被给从还你")
def ratio(s):
    c=[x for x in s if '\u4e00'<=x<='\u9fff']
    if not c: return 0.0,0
    return sum(1 for x in c if x in common)/len(c),len(c)
files=sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True))+glob.glob("entry/src/main/ets/**/*.ts",recursive=True)
bad=[];clean=[]
for p in files:
    s=open(p,encoding="utf-8").read()
    r0,n0=ratio(s)
    dec=s.encode("gb18030").decode("utf-8",errors="replace")
    r1,_=ratio(dec)
    if r1>=0.30 and r1>r0+0.12: bad.append((round(r1,2),p))
    else: clean.append(p)
print("CORRUPT",len(bad))
for r,p in bad: print(r,p)
print("CLEAN",len(clean))
