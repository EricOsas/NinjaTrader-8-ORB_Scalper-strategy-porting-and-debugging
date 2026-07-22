import os
import re

dir_path = r'C:\Users\osamwonyieric\AppData\Roaming\MetaQuotes\Terminal\F49F6D84DE337BA25E6F8205834F0EB8\MQL5\Experts\DTR-CRT'

# 1. DTR_CRT.mq5
with open(os.path.join(dir_path, 'DTR_CRT.mq5'), 'r', encoding='utf8') as f:
    text = f.read()

# Replace everything from ENUM_CISD_MODE to the end of the inputs block with #include "DTR_Inputs.mqh"
start_str = '//| Enumerations                                                     |'
end_str = '//+------------------------------------------------------------------+\n//| Global State                                                     |'
start_idx = text.find(start_str)
end_idx = text.find(end_str)

if start_idx != -1 and end_idx != -1:
    text = text[:start_idx] + '#include "DTR_Inputs.mqh"\n\n' + text[end_idx:]
    with open(os.path.join(dir_path, 'DTR_CRT.mq5'), 'w', encoding='utf8') as f:
        f.write(text)

# 2. DTR_Core.mqh
with open(os.path.join(dir_path, 'DTR_Core.mqh'), 'r', encoding='utf8') as f:
    text = f.read()
text = re.sub(r'extern\s+(int|bool|double|color|ENUM_\w+)\s+Inp_\w+\s*;\s*', '', text)
text = text.replace('#include <Trade\\Trade.mqh>', '#include <Trade\\Trade.mqh>\n#include "DTR_Inputs.mqh"')
with open(os.path.join(dir_path, 'DTR_Core.mqh'), 'w', encoding='utf8') as f:
    f.write(text)

# 3. DTR_Engine.mqh
with open(os.path.join(dir_path, 'DTR_Engine.mqh'), 'r', encoding='utf8') as f:
    text = f.read()
text = re.sub(r'extern\s+(int|bool|double|color|ENUM_\w+)\s+Inp_\w+\s*;\s*', '', text)
text = text.replace('#include "DTR_Core.mqh"', '#include "DTR_Core.mqh"\n#include "DTR_Inputs.mqh"')
with open(os.path.join(dir_path, 'DTR_Engine.mqh'), 'w', encoding='utf8') as f:
    f.write(text)

# 4. DTR_UI.mqh
with open(os.path.join(dir_path, 'DTR_UI.mqh'), 'r', encoding='utf8') as f:
    text = f.read()
text = re.sub(r'extern\s+(int|bool|double|color|ENUM_\w+)\s+Inp_\w+\s*;\s*', '', text)
text = text.replace('#include "DTR_Core.mqh"', '#include "DTR_Core.mqh"\n#include "DTR_Inputs.mqh"')
with open(os.path.join(dir_path, 'DTR_UI.mqh'), 'w', encoding='utf8') as f:
    f.write(text)

print('SUCCESS')
