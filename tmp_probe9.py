import glob
cs=set(open("headchars.txt",encoding="utf-8").read())
files=sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True))+glob.glob("entry/src/main/ets/**/*.ts",recursive=True)
bad=[];clean=[]
for p in files:
    s=open(p,encoding="utf-8").read()
    cj=[c for c in s if '\u4e00'<=c<='\u9fff']
    if len(cj)<5: clean.append(p); continue
    known=sum(1 for c in cj if c in cs)/len(cj)
    (bad if known<0.5 else clean).append(p)
print("CORRUPT",len(bad))
for p in bad: print(" ",p)
print("CLEAN",len(clean))
