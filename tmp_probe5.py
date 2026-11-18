p="entry/src/main/ets/ui/components/BootSplash.ets"
s=open(p,encoding="utf-8").read()
for enc in ["gb18030","gbk","cp936","big5","shift_jis"]:
    try:
        dec=s.encode(enc,errors="strict").decode("utf-8",errors="replace")
    except Exception as e:
        print(enc,"ERR",type(e).__name__); continue
    print(enc,"ok", dec.count("\ufffd"))
    for l in dec.splitlines():
        if "Text(" in l and any('\u4e00'<=c<='\u9fff' for c in l):
            print("   ",l.encode("unicode_escape").decode())
