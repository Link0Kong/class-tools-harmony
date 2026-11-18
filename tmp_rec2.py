p="entry/src/main/ets/ui/components/BootSplash.ets"
lines=open(p,encoding="utf-8").read().split("\n")
l=lines[142]
print(repr(l)[:200])
b=l.encode("gb18030","replace")
dec=b.decode("utf-8","replace")
print(repr(dec)[:200])
print("equal?",dec==l)
print("cjk",sum(1 for c in dec if '\u4e00'<=c<='\u9fff'),"bad",dec.count("\ufffd"))
