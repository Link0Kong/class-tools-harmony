p="entry/src/main/ets/ui/components/BootSplash.ets"
lines=open(p,"rb").read().split(b"\n")
for i in range(138,152):
    print(i+1, lines[i][:100])
