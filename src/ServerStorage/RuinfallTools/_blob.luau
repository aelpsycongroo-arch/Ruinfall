-- dev helper: reads text packed into a PNG in Studio's content folder (rbxasset://ruinfall/<name>)
return function(name)
	local AS = game:GetService("AssetService")
	local ei = AS:CreateEditableImageAsync(Content.fromUri("rbxasset://ruinfall/" .. name))
	local size = ei.Size
	local buf = ei:ReadPixelsBuffer(Vector2.zero, size)
	ei:Destroy()
	local npix = size.X * size.Y
	local raw = buffer.create(npix * 3)
	for i = 0, npix - 1 do
		buffer.writeu8(raw, i * 3, buffer.readu8(buf, i * 4))
		buffer.writeu8(raw, i * 3 + 1, buffer.readu8(buf, i * 4 + 1))
		buffer.writeu8(raw, i * 3 + 2, buffer.readu8(buf, i * 4 + 2))
	end
	local len = buffer.readu8(raw, 0) * 16777216 + buffer.readu8(raw, 1) * 65536 + buffer.readu8(raw, 2) * 256 + buffer.readu8(raw, 3)
	local text = buffer.readstring(raw, 4, len)
	local v = 0
	for i = 1, #text do
		v = (v * 31 + string.byte(text, i)) % 1000000007
	end
	return text, v
end
