import io
P = 'lib/screens/settings_screen.dart'
T = io.open(P, encoding='utf-8', newline='').read()
O = "                Text(title, style: DraftText.display(18, c.tx)),\n"
N = "                Expanded(\n                  child: Text(\n                    title,\n                    maxLines: 1,\n                    overflow: TextOverflow.ellipsis,\n                    style: DraftText.display(18, c.tx),\n                  ),\n                ),\n"
assert T.count(O) == 1
T = T.replace(O, N)
io.open(P, 'w', encoding='utf-8', newline='').write(T)
print('patched', len(T))
