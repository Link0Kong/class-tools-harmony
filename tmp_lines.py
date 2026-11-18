p="entry/src/main/ets/ui/screens/HomeScreen.ets"
b=open(p,"rb").read()
lines=b.split(b"\n")
for i in (59,60,89,92,98,110):
    print(i+1, lines[i][:120])
