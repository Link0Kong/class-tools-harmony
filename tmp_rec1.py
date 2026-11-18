import glob,sys

def recover_line(line):
    b=line.encode("gb18030","replace")
    dec=b.decode("utf-8","replace")
    if dec==line: return line
    ncjk=sum(1 for c in dec if '\u4e00'<=c<='\u9fff')
    nbad=dec.count("\ufffd")
    if ncjk>=1 and nbad<=max(2,ncjk*0.2):
        return dec
    return line

for p in ["entry/src/main/ets/ui/screens/AllScreen.ets","entry/src/main/ets/ui/theme/Breakpoints.ets","entry/src/main/ets/ui/components/BootSplash.ets"]:
    lines=open(p,encoding="utf-8").read().split("\n")
    ch=0
    out=[]
    for l in lines:
        r=recover_line(l)
        if r!=l: ch+=1
        out.append(r)
    print("==",p,"changed lines",ch)
    for l in out:
        if '\u4e00'<=l and any('\u4e00'<=c<='\u9fff' for c in l):
            pass
    sample=[l for l in out if "\ufffd" in l][:6]
    for l in sample: print("  RESID:",l.encode("unicode_escape").decode())
