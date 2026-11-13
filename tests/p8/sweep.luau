-- tests/p8: a full UI check on the client (make_sweep.py): buttons and labels outside their panel, button overlaps, small text.
-- Runs via MCP execute_luau (Client) from p8lib.sweep(); returns the summary text.
local pg=game.Players.LocalPlayer.PlayerGui
local function shown(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
local function rect(o) local a=o.AbsolutePosition local s=o.AbsoluteSize return {a.X,a.Y,a.X+s.X,a.Y+s.Y} end
local function inside(a,b,t) return a[1]>=b[1]-t and a[2]>=b[2]-t and a[3]<=b[3]+t and a[4]<=b[4]+t end
local skip={LoadingScreen=true,TouchGui=true,Freecam=true,BubbleChat=true,ProximityPrompts=true} -- the Roblox prompt window (not ours; its appear animation shifts the text)
local issues, small = {}, {}
for _,g in pg:GetChildren() do if g:IsA('ScreenGui') and g.Enabled and not skip[g.Name] then
  local bs={}
  for _,o in g:GetDescendants() do
    if o:IsA('GuiObject') and shown(o) and o.AbsoluteSize.X>1 and o.AbsoluteSize.Y>1 then
      local isText = (o:IsA('TextLabel') or o:IsA('TextButton')) and (o :: any).ContentText~=''
      if o:IsA('GuiButton') or isText then
        local p=o.Parent local cont=nil local inScroll=false
        while p and p~=g do
          if p:IsA('ScrollingFrame') then inScroll=true break end
          if p:IsA('Frame') and p.BackgroundTransparency<0.95 and p.AbsoluteSize.X>60 and p.AbsoluteSize.Y>30 then cont=p break end
          p=p.Parent
        end
        if cont and not inScroll and o.Name~='Close' and not inside(rect(o),rect(cont),3) then
          local r,c=rect(o),rect(cont)
          issues[#issues+1]=string.format('%s: %s OUT of %s by L%d T%d R%d B%d',g.Name,o:GetFullName():sub(-38),cont.Name,math.max(0,c[1]-r[1]),math.max(0,c[2]-r[2]),math.max(0,r[3]-c[3]),math.max(0,r[4]-c[4]))
        end
        if isText and (o :: any).TextBounds.Y>0 and (o :: any).TextBounds.Y<11 and not inScroll then small[#small+1]=g.Name..':'..o.Name..'='..math.floor((o :: any).TextBounds.Y) end
      end
      if o:IsA('GuiButton') and o.Name~='Dim' and not o:FindFirstAncestorWhichIsA('ScrollingFrame') then bs[#bs+1]=o end
    end
  end
  for i=1,#bs do for j=i+1,#bs do local A,B=bs[i],bs[j] if not (A:IsAncestorOf(B) or B:IsAncestorOf(A)) then local a,b=rect(A),rect(B)
    if a[1]<b[3]-2 and b[1]<a[3]-2 and a[2]<b[4]-2 and b[2]<a[4]-2 then issues[#issues+1]=g.Name..': '..A.Name..' X '..B.Name end end end end
end end
return 'ISSUES['..#issues..'] '..table.concat(issues,' ; ')..' || SMALL['..#small..'] '..table.concat(small,', ')
