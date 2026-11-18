import glob
files=sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True))+glob.glob("entry/src/main/ets/**/*.ts",recursive=True)+glob.glob("entry/src/main/ets/**/*.json5",recursive=True)
tot=0;badfiles=0
for p in files:
    s=open(p,encoding="utf-8").read()
    try:
        dec=s.encode("gb18030").decode("utf-8",errors="replace")
    except UnicodeEncodeError as e:
        badfiles+=1; print("ENCERR",p); continue
    n=dec.count("\ufffd")
    if n: print(f"{n:4d} {p}")
    tot+=n
print("total fffd",tot,"encode-err files",badfiles)
