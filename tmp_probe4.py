import sys
p="entry/src/main/ets/ui/components/BootSplash.ets"
s=open(p,encoding="utf-8").read()
dec=s.encode("gbk",errors="replace").decode("utf-8",errors="replace")
out=[l for l in dec.splitlines() if any('\u4e00'<=c<='\u9fff' for c in l)]
print("\n".join(out).encode("unicode_escape").decode())
