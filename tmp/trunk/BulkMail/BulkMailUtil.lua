ace:RegisterFunctions({
version = 1.01,

BuildItemLink = function(c,i,n)
	if(((c or "")=="") or ((i or "")=="") or ((n or "")=="")) then return "" end
	if(strlen(c)<8) then c="ff"..strlower(c) end
	return format("|c%s|Hitem:%s|h[%s]|h|r",c,i,n)
end,
})
