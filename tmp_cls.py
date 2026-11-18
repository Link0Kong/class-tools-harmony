import glob,subprocess
cs=set(open("headchars.txt",encoding="utf-8").read())
def known_ratio(s):
    c=[x for x in s if '\u4e00'<=x<='\u9fff']
    if not c: return 1.0,len(c)
    return sum(1 for x in c if x in cs)/len(c),len(c)
rows=[]
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    s=open(p,encoding="utf-8").read()
    r,n=known_ratio(s)
    rows.append((r,n,p))
rows.sort()
for r,n,p in rows[:30]: print(f"{r:.3f} {n:5d} {p}")
print("...")
for r,n,p in rows[30:45]: print(f"{r:.3f} {n:5d} {p}")
