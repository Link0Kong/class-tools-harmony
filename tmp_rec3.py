import glob
def cjk(s): return sum(1 for c in s if '\u4e00'<=c<='\u9fff')
def rec_line(l):
    try: b=l.encode("gb18030")
    except UnicodeEncodeError: b=l.encode("gb18030","replace")
    d=b.decode("utf-8","replace")
    if d==l: return None
    cd=cjk(d); cs=cjk(l); f=d.count("\ufffd")
    if cd>0 and cd>=0.5*cs and f<=0.5*cd: return d
    return None
tot=0
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    s=open(p,encoding="utf-8").read()
    n=0; ff=0
    for l in s.split("\n"):
        r=rec_line(l)
        if r is not None:
            n+=1; ff+=r.count("\ufffd")
    if n: print(f"lines={n:4d} fffd={ff:4d} {p}")
    tot+=ff
print("TOTAL fffd",tot)
