import glob
pat="\ufffd"
import re
tot=0
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    s=open(p,encoding="utf-8").read()
    n=len(re.findall(r"[\u4e00-\u9fff]\?(?=[;,)\]}']|$)", s))
    if n: print(n,p); tot+=n
print("TOTAL",tot)
