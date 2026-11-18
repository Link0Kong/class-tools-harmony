s=open("entry/src/main/ets/ui/components/BootSplash.ets",encoding="utf-8").read().splitlines()
for i in (142,):
    l=s[i]
    print(i+1, " ".join(f"U+{ord(c):04X}" for c in l if ord(c)>127 or c in "'?()"), "|", l.encode("unicode_escape").decode())
