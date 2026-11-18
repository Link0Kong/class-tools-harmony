import sys
def rec(s): return s.encode("gb18030","replace").decode("utf-8","replace")
for p in ["entry/src/main/ets/ui/screens/HomeScreen.ets","entry/src/main/ets/ui/tools/RosterScreen.ets"]:
    s=open(p,encoding="utf-8").read()
    # recover line by line
    out=[]
    for l in s.split("\n"):
        nb=sum(1 for c in l if '\ue000'<=c<='\uf8ff')
        if nb>0 or any('\u9000'<=c<='\u9fff' for c in l) and any(c in "鈥鍜鐨鏄涓浣" for c in l):
            pass
        out.append(rec(l))
    r="\n".join(out)
    print("=====",p, "fffd", r.count("\ufffd"))
    idx=0; n=0
    while True:
        i=r.find("\ufffd",idx)
        if i<0 or n>=14: break
        print("  ", r[max(0,i-45):i+18].replace("\n","\\n").encode("unicode_escape").decode())
        idx=i+1; n+=1
