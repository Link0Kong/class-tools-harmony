cs=set(open("headchars.txt",encoding="utf-8").read())
for p in ["entry/src/main/ets/ui/screens/AllScreen.ets","entry/src/main/ets/ui/components/PageHeader.ets","entry/src/main/ets/ui/components/SectionHeader.ets","entry/src/main/ets/ui/components/ToolTile.ets","entry/src/main/ets/ui/components/GlassBar.ets","entry/src/main/ets/ui/theme/Tokens.ets"]:
    s=open(p,encoding="utf-8").read()
    cj=[c for c in s if '\u4e00'<=c<='\u9fff']
    known=sum(1 for c in cj if c in cs)/max(1,len(cj))
    print(round(known,3),len(cj),p)
