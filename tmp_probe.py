import sys,glob,os
root=r"entry/src/main/ets"
files=[p for p in glob.glob(root+"/**/*.ets",recursive=True)]
for p in files:
    s=open(p,encoding="utf-8").read()
    if not any('\u4e00'<=c<='\u9fff' for c in s): continue
    b=s.encode("gbk",errors="replace")
    dec=b.decode("utf-8",errors="replace")
    n=dec.count("\ufffd")
    if n: print(f"{n:5d} {p}")
