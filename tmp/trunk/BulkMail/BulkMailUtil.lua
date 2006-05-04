ace:RegisterFunctions({
version = 1.01,

GetItemInfoFromLink = function(l)
	if(not l) then return end
	local _,_,c,id,il,n=strfind(l,"|cff(%x+)|Hitem:(%d+)(:%d+:%d+:%d+)|h%[(.-)%]|h|r")
	return n,c,id..il,id
end,

BuildItemLink = function(c,i,n)
	if(((c or "")=="") or ((i or "")=="") or ((n or "")=="")) then return "" end
	if(strlen(c)<8) then c="ff"..strlower(c) end
	return format("|c%s|Hitem:%s|h[%s]|h|r",c,i,n)
end,
})
