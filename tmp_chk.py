for p in ["entry/src/main/ets/ui/components/BootSplash.ets","entry/src/main/ets/ui/screens/HomeScreen.ets","entry/src/main/ets/ui/screens/IdentityScreen.ets","entry/src/main/ets/ui/tools/NoticeScreen.ets"]:
    b=open(p,"rb").read()
    try:
        s=b.decode("utf-8"); print("utf8 OK",p,len(s))
    except UnicodeDecodeError as e:
        print("utf8 FAIL",p,e)
        print("   ",b[max(0,e.start-30):e.end+30])
