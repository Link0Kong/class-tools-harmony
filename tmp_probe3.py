import glob
common=set("的了是在不有和人我他你个上们这中大为来以就要可到说地对与也把被给从到还")
def ratio(s):
    c=[x for x in s if '\u4e00'<=x<='\u9fff']
    if not c: return 0.0,len(c)
    return sum(1 for x in c if x in common)/len(c),len(c)
files=sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True))+glob.glob("entry/src/main/ets/**/*.ts",recursive=True)
bad=[];good=[]
for p in files:
    s=open(p,encoding="utf-8").read()
    r0,n0=ratio(s)
    if n0<3: continue
    dec=s.encode("gbk",errors="replace").decode("utf-8",errors="replace")
    r1,n1=ratio(dec)
    if r1>0.25 and r1>r0*3: bad.append(p)
    else: good.append(p)
print("CORRUPT",len(bad))
for p in bad: print(" ",p)
print("CLEAN",len(good))
