#!/usr/bin/env python3
"""Synchronize implementation facts in the DOCX while preserving its package.

The original design remains available in Git. Appendix B is replaced on every
run; future version-one requirements are retained and explicitly marked pending.
"""
from pathlib import Path
import copy
import hashlib
import json
import io
import xml.etree.ElementTree as ET
import zipfile
ROOT=Path(__file__).resolve().parents[1]
DOC=ROOT/'Assembly_BASIC_C64_Design.docx'
W='http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS={'w':W}
ET.register_namespace('w',W)

def namespaces(data):
    result=dict(value for _,value in ET.iterparse(io.BytesIO(data),events=['start-ns']))
    for prefix,uri in result.items():ET.register_namespace(prefix,uri)
    return result

def serialize(root,declared):
    data=ET.tostring(root,encoding='utf-8',xml_declaration=True)
    # Preserve unused declarations, including prefixes named by mc:Ignorable.
    extras=''.join(f' xmlns:{p}="{uri}"' for p,uri in declared.items()
                   if p and f'xmlns:{p}='.encode() not in data)
    end=data.index(b'>',data.index(b'?>')+2)
    return data[:end]+extras.encode()+data[end:]

def paragraph(text,heading=False):
    p=ET.Element(f'{{{W}}}p')
    if heading:
        properties=ET.SubElement(p,f'{{{W}}}pPr')
        ET.SubElement(properties,f'{{{W}}}pStyle',{f'{{{W}}}val':'Heading1'})
    run=ET.SubElement(p,f'{{{W}}}r')
    t=ET.SubElement(run,f'{{{W}}}t')
    t.text=text;t.set('{http://www.w3.org/XML/1998/namespace}space','preserve')
    return p

def synchronize():
    report=json.loads((ROOT/'build/size-report.json').read_text())
    tests=json.loads((ROOT/'build/test-report.json').read_text())
    assert tests['failures']==tests['errors']==0, 'Fix test failures before synchronizing the design'
    assert tests['rom_sha256']==report['rom_sha256'], 'Tests refer to a different cartridge build'
    design_before=hashlib.sha256(DOC.read_bytes()).hexdigest()
    with zipfile.ZipFile(DOC) as z:
        entries=[(info,z.read(info.filename)) for info in z.infolist()]
    original=dict((i.filename,b) for i,b in entries)['word/document.xml']
    declared=namespaces(original)
    root=ET.fromstring(original)
    body=root.find('w:body',NS)
    for child in list(body):
        value=''.join(child.itertext())
        if value.startswith('Appendix B — implementation status'):
            start=list(body).index(child)
            for old in list(body)[start:]:
                if old.tag!=f'{{{W}}}sectPr':body.remove(old)
            break
    replacements={
        'Design specification  |  Version 0.11  |  13 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        'Design specification  |  Version 0.9  |  13 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        'ABI 5':'ABI 7',
        'ABI 6':'ABI 7',
        'Version 0.10':'Version 0.12',
        '16.8 fixed-point':'16.16 fixed-point',
        'Design specification  |  Version 0.8  |  12 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        'Design specification  |  Version 0.7  |  12 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        'Design specification  |  Version 0.6  |  10 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        'ABI 4':'ABI 7',
        'Design specification  |  Version 0.3  |  9 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        'Design specification  |  Version 0.5  |  9 October 2026':
        'Design specification  |  Version 0.12  |  14 October 2026',
        '$E800-$FFF9':'$E400-$FFF9', '$E000-$E7FF':'$E000-$E3FF',
        '[$E000,$E800)':'[$E000,$E400)', '49 KiB':'42 KiB', '48 KiB':'42 KiB',
        'Version 0.4':'Version 0.12', 'runtime ABI 2':'runtime ABI 7', 'ABI 2':'ABI 7',
        'runtime ABI 3':'runtime ABI 7', 'ABI 3':'ABI 7',
        'Normal cartridge and CPU maps':'Magic Desk cartridge and CPU maps',
        'Release only when the standard cartridge boots':'Release only when the Magic Desk cartridge boots',
        'roughly 379 such lines':'roughly 322 such lines',
        '6138 bytes':'7162 bytes', '6138':'7162',
        'proposed $E800 base':'implemented $E400 base',
        'roughly 389 such lines':'roughly 322 such lines',
    }
    rewrites={
        'Link the execution image for its fixed run addresses':
        'Link the execution runtime for fixed run addresses $E400-$FFF9 and the resident compiler for $1400-$2BFF (runtime ABI 3). Store a deterministic LZSS-compressed load image in the standard cartridge and decompress it through common-RAM read gates at cold start; refresh the runtime at RUN and CONT. Both images have separate fixed-address link outputs. The linker emits the RAM runtime as a separate fixed-address binary before compression; all internal calls already name its RAM run addresses. Copy the complete dependency closure, including helper code, tables, constants and diagnostics. No arbitrary relocation of ROM instructions is assumed.',
        'The allocator therefore has two spans:':
        'The implemented allocator has two spans: [$2C00,$D000) and [$E000,$E400). Their raw total is 42 KiB (43008 bytes), before anchors, names, source, generated code, arrays, strings and free-block overhead. The $1400-$2BFF range is permanently reserved for a 6 KiB compiler image decompressed at startup. The $E000-$E3FF shadow span supplies 1 KiB; $E400-$FFFF is permanently reserved for the runtime and six vector bytes. This is the lower-runtime-base adjustment permitted by the original design.',
        'These sizes are proposed budgets.':
        'These are ABI 3 build limits. Runtime helpers have 7162 bytes at $E400-$FFF9; the measured image occupies 6386 bytes. Any future runtime-base change requires a new ABI/build identifier and recompilation. ROM-off execution remains required. No allocation may cross the I/O hole, overlap the runtime or assume visibility during a ROM gateway.',
        'Runtime string collection may move string payloads':
        'The implemented runtime collector is nonmoving mark-and-sweep with free-list coalescing. It never moves string payloads, line code or native return addresses. It enumerates physical allocation boundaries and retains objects reachable from source, slabs, names/bindings, arrays/functions, descriptors, expression temporaries and live helper roots. It marks roots once per 2 KiB address window in a 256-byte bitmap over inactive lexer/compiler scratch at $0E00-$0EFF. A monotonic sorted-free-list cursor avoids repeated searches while inserting reclaimed blocks; coalescing follows the sweep. Headers retain full 16-bit allocation sizes. All collection boundaries occur outside active lexing/compilation, and no additional user-arena allocation is needed. It runs wholly within copied RAM helpers. Fragmentation can prevent allocation despite sufficient total free bytes. Direct CLEAN now rebuilds source, anchors and bindings into a second graph, densely remaps names, clears values/continuations and collects the released graph. It requires temporary headroom; general sliding arena compaction remains pending.',
        'Use compacting mark-and-copy or sliding collection':
        'Use the implemented nonmoving mark-and-sweep collector with registered descriptor and helper roots. Roots include scalar cells, array elements, expression temporaries and function state. Allocating helpers must publish temporary string pointers before a collection boundary. Pointer rewriting is unnecessary because payloads remain stationary; the tradeoff is fragmentation. Clear temporary roots at statement completion and error exit.',
        'Intern each full normalized spelling into a name dictionary':
        'Intern each complete normalized spelling into a dictionary with a one-byte length, full name bytes and a 16-bit ID. The implementation compares complete spellings in a linked dictionary rather than using the proposed hash buckets. This has linear compile-time lookup cost but preserves every character and suffix. Scalar cells and separate array/function bindings remain stable; repeated source references carry IDs rather than repeated spellings. A, A% and A$ and SCORE and SCORETOTAL remain distinct.',
        'Bind all references during compilation so ordinary scalar accesses':
        'Bind scalar references during compilation so native accesses name stable cells without runtime full-name lookup. Dictionary lookup and storage grow with complete spellings; repeated token references remain compact. Retain interned names and cells until NEW or a successful CLEAN rebuild that rebinds all source and code. Deletion cannot free a cell still referenced by native code. RUN clears values while retaining bindings.',
        'These are planning allocations, not measured sizes.':
        'The preceding subdivision is the original planning allocation. ABI 3 measured link sizes are recorded in Appendix B and dist/size-report.json. The compressed runtime consumes ROM as well as 6386 bytes in its 7162-byte RAM reservation. Gateway code consumes both low-RAM workspace and cartridge space. The build enforces the 16384-byte cartridge, 768-byte gateway and 7162-byte runtime limits.',
    }
    rewrites['These sizes are proposed budgets.']=rewrites['These sizes are proposed budgets.'].replace('6386',str(report['runtime_used_bytes']))
    rewrites['These are ABI 3 build limits.']=rewrites['These sizes are proposed budgets.']
    measured=('The preceding subdivision is the original planning allocation. ABI 3 measured link sizes '
              'are recorded in Appendix B and dist/size-report.json. The compressed runtime consumes ROM '
              f"as well as {report['runtime_used_bytes']} bytes in its {report['runtime_budget_bytes']}-byte "
              'RAM reservation. Gateway code consumes both low-RAM workspace and cartridge space. '
              'The build enforces the 16384-byte cartridge, 768-byte gateway, 6144-byte compiler and 7162-byte runtime limits.')
    rewrites['These are planning allocations, not measured sizes.']=measured
    rewrites['The preceding subdivision is the original planning allocation.']=measured
    rewrites.update({
        'Link the execution image for fixed run addresses': rewrites['Link the execution image for its fixed run addresses'],
        'Link the execution runtime for fixed run addresses': rewrites['Link the execution image for its fixed run addresses'],
        'The implemented allocator has two spans:': rewrites['The allocator therefore has two spans:'],
        'The implemented runtime collector is': rewrites['Runtime string collection may move string payloads'],
        'Bind scalar references during compilation': rewrites['Bind all references during compilation so ordinary scalar accesses'],
        'Fractional constants, E-format constants':
        'Fractional constants, E-format constants, π, SIN, COS, TAN, ATN, EXP, LOG and SQR have no floating-point fallback. RND is implemented as a random 16-bit integer function in revision 0.5.',
        'Preserve BASIC V2 precedence and evaluation order':
        'Preserve eager integer evaluation and BASIC precedence with shifts inserted below addition and above comparisons. Highest to lowest: power (left associative), unary +/- , multiplication/division, addition/subtraction, << and >> (left associative), comparisons, NOT, AND, OR. Relational results are -1 or 0. Shift counts are checked unsigned bytes 0..255. Left shifts wrap the word; arithmetic right shifts repeat its sign bit. Counts of 16 or more produce zero or sign fill. Numeric/string mixing requires explicit conversion; string comparisons use unsigned PETSCII order then length.',
        'Every native body ends physically':
        'Every native body ends physically with its patchable successor JMP. IF ... THEN ... ELSE selects one colon-separated arm for the remainder of its physical line. ELSE binds to the nearest unmatched IF; either arm can be a literal line target. A false IF without ELSE reaches the trailer. Nested IF depth is bounded to 32 and per-line IF patches to 64; a bound failure retains source with a FORMULA TOO COMPLEX stub.',
        'Retain malformed and unsupported source in defined tokens':
        'Retain malformed and unsupported source in defined tokens so it can be LISTed and repaired. Numbered submission reports lexical/assembly failure immediately, while saving tokens and a deferred runtime error stub; successful submission and deletion resume input without READY. An enclosing false IF still skips its malformed unchosen body. Resource failure retains the previous source/code payload.',
        'READY runs the editor/compiler in the command map':
        'READY runs the editor/compiler in the command map. Send the screen-editor carriage return returned by CHRIN to CHROUT before parsing every submitted command, numbered line, deletion or blank line. This advances the cursor before subsequent output or input. Successful numbered entry/deletion resumes input without another READY prompt. Recoverable lexical/assembly failure prints an error but saves the new line. Direct LIST starts on a new line and accepts LIST n, LIST low-high and open endpoints; bounds are inclusive unsigned line numbers 0..63999 and reversed bounds give an empty listing. Direct CLEAN rebuilds dense slabs/symbols, clears variables and invalidates CONT. Other direct statements compile into a transient native payload and synthetic anchor, execute through the RAM gateway and end at DIRECT_DONE.',
    })
    rewrites['Audit zero-page ownership for every supported KERNAL operation.'] = (
        'Audit zero-page ownership for every supported KERNAL operation. Save overlapping language '
        'temporaries or avoid the locations. Place indirect-JMP pointers away from a low byte of $FF '
        'to avoid the NMOS page-boundary bug. RESERVE address,bytes is an implemented compile-time '
        'declaration outside IF: both unsigned numeric literals must be multiples of 256, with a '
        'nonzero range wholly inside a free portion of one user-arena span. Declare up to eight '
        'regions before allocating the program, normally on its first numbered line. Allocation '
        'and collection exclude the full region, with bounds stored outside user RAM. RUN, CLR, '
        'edits and CLEAN preserve reservations; NEW releases them. SAVE/LOAD retain numbered '
        'declarations. Identical bounds are idempotent; occupied/overlapping bounds fail safely. '
        'Removing source or a failed import may leave a reservation until NEW. $C000 is not implicit '
        'scratch RAM, and stock BASIC memory-top POKEs at 55/56 do not configure this allocator.')
    rewrites['READY runs the editor/compiler in the command map'] += (' Direct BASIC opens the bank-3 split editor: 20 listing rows, one status row and four edit/output rows. F1 shows help; F7/QUIT close and clear, and RUN closes before execution. Bookmarks retain selected and top BASIC line numbers. Return copies the selection or submits a draft; left-arrow changes focus and discards the draft on return to the list. INS cycles insert, overwrite and literal control-glyph modes. Errors preserve drafts and place the cursor at the pane top right, with diagnostics in the status bar. Keyboard INPUT, output and screen-clear controls stay within the pane, with no READY prompt. The visible draft is limited to 160 bytes; overlong source copying is rejected without truncation. KERNAL input/output vectors are restored on exit.')
    # Revision 0.6 changes the hardware/load contract while preserving source semantics.
    image=('Link the execution runtime for fixed run addresses $E400-$FFF9 and the resident '
           'compiler for $1400-$2BFF (runtime ABI 7). Store raw load images in Magic Desk banks '
           '2 and 1 respectively. Copy the complete dependency closures through common RAM at '
           'cold start; refresh the runtime at RUN and CONT. The linker supplies separate load '
           'and run addresses, so internal instructions already name their RAM addresses. '
           'Copy service entry stubs to $0334-$03FF after KERNAL initialization. Bank-2 DATA/READ/RESTORE, DEF FN activation and device/input services execute directly from ROM through the generic common-RAM bank_call ABI. Shared hot helpers remain in the copied runtime. There is no decompression or arbitrary instruction relocation.')
    for key in ('Link the execution image for its fixed run addresses',
                'Link the execution image for fixed run addresses',
                'Link the execution runtime for fixed run addresses'):
        rewrites[key]=image
    for key in ('The allocator therefore has two spans:', 'The implemented allocator has two spans:'):
        rewrites[key]=rewrites[key].replace('decompressed at startup','copied from bank 1 at startup')
    budget=(f"These are ABI 7 build limits. The 65536-byte cartridge has eight 8192-byte banks. "
            f"Runtime helpers occupy {report['runtime_used_bytes']} of 7162 bytes at $E400-$FFF9; "
            f"the compiler occupies {report['compiler_used_bytes']} of 6144 bytes at $1400-$2BFF; "
            f"the gateway occupies {report['gateway_used_bytes']} of 768 bytes and service entry stubs occupy {report['service_gateway_used_bytes']} of 204 bytes at $0334-$03FF. Native ROM-off execution "
            'remains required. No allocation may cross the I/O hole or overlap firmware. '
            'Future RAM-layout changes require a new ABI and source recompilation.')
    for key in ('These sizes are proposed budgets.', 'These are ABI 3 build limits.',
                'These are ABI 4 build limits.', 'These are ABI 5 build limits.', 'These are ABI 6 build limits.', 'These are ABI 7 build limits.'):
        rewrites[key]=budget
    measured=('The preceding subdivision is the current bank allocation. Exact measured link '
              'sizes are recorded in Appendix B and dist/size-report.json. Compiler and runtime '
              'load images are raw. The build enforces a 65536-byte cartridge, each 8192-byte '
              'bank, a 768-byte gateway, a 6144-byte resident compiler and a 7162-byte RAM runtime. '
              'Reserved banks anticipate future features; they do not imply those features exist '
              'or enlarge the current 43008-byte raw program arena.')
    for key in ('These are planning allocations, not measured sizes.',
                'The preceding subdivision is the original planning allocation.',
                'The preceding subdivision is the current bank allocation.'):
        rewrites[key]=measured
    rewrites.update({
        'Serial source files are streamed as bounded chunks through common RAM.':
        'Serial source files are streamed as bounded chunks through common RAM. Do not call an unrestricted KERNAL LOAD into the enlarged arena: it could overwrite compiled code, low gateways or the runtime image. Long IEC operations may delay abort servicing until protocol-safe return, but polling resumes afterward. KERNAL-owned state remains excluded from the arena. With tape transport unsupported, $0334-$03FF is reserved, currently unassigned common RAM for future firmware code, data or workspace. Bank gateways are prospective; other implementation uses remain open. Install future contents only after KERNAL initialization because RAMTAS clears page 3; preserve the KERNAL vectors through $0333.',
        'Implement Assembly BASIC as a normal 16 KB':
        'Implement Assembly BASIC as a 64 KiB classic Magic Desk autostart cartridge containing '
        'the command/editor firmware, tokenizer, compiler and an execution runtime load image. '
        'Copy compiler/runtime helpers to fixed RAM and execute native programs with cartridge, '
        'BASIC and KERNAL ROM hidden. Retain custom tokens beside native code and link each body '
        'through its final successor JMP. LIST expands source tokens into canonical PETSCII.',
        'Standard 16 KB cartridge with':
        '64 KiB classic Magic Desk cartridge, eight 8 KiB ROML banks selected through $DE00; '
        '/EXROM low and /GAME high. No cartridge RAM is required.',
        'Use a standard 16 KB cartridge decoding':
        'Use a 64 KiB classic Magic Desk cartridge with eight banks at $8000-$9FFF, /EXROM low '
        'and /GAME high. $DE00 selects banks 0..7; its write-only latch is shadowed at $0BE3. '
        'The command map sets LORAM, HIRAM and CHAREN: bank 0, stock BASIC at $A000-$BFFF, '
        'I/O and KERNAL are visible. No stock BASIC routines are called. Preserve cassette '
        'control bits and configure direction bits 0..2 as outputs. See docs/MAGIC_DESK_BANKS.md '
        'and the VICE Magic Desk format specification.',
        'Cartridge at $8000-$BFFF;':
        'Selected Magic Desk bank at $8000-$9FFF; BASIC ROM at $A000-$BFFF; I/O at $D000-$DFFF; KERNAL at $E000-$FFFF.',
        'With a normal 16 KB cartridge,':
        'With classic Magic Desk, $35 hides ROML, BASIC and KERNAL while retaining I/O; $34 '
        'hides I/O too. Writes beneath visible ROM reach underlying RAM. Keep the cartridge '
        'enabled and select RAM through $01 rather than writing $80 to $DE00, since some '
        'physical variants latch disable until reset. VIC visibility follows its separate map.',
        'The KERNAL recognizes this signature':
        'The KERNAL recognizes CBM80 at $8004 before initialization. Bank 0 has cold/warm '
        'entry vectors at $8000/$8002. Every auxiliary bank has the same signature and vectors '
        'to common-RAM recovery helpers installed at startup; these select bank 0 before '
        'returning to command ROM. The previous $A000 recovery words are removed because '
        'stock BASIC ROM occupies that window in the command map.',
        'Save the caller’s low three mapping bits':
        'KERNAL gateways save low mapping bits, interrupt state and the bank shadow. Expose '
        'I/O before selecting bank 0, preserve service arguments/results and carry, and restore '
        'the bank before restoring the map. Preserve the current upper port bits for device '
        'services. Image-copy gateways instead mask IRQs for the complete copy and restore '
        'the full saved port, bank and flags. Every $DE00 selection and its return path must '
        'execute in common RAM. NMI stays in common RAM and leaves the bank unchanged.',
        '16 KB ROM/.CRT;':
        '64 KiB Magic Desk ROM/.CRT; eight 8 KiB CHIP packets, autostart, $37/$35 mapping, raw image copies, bank-preserving low-RAM gateways and RAM vectors validated.',
    })
    replacements.update({
        'PRINT and STR$ continue to use signed runtime formatting.':
        'PRINT and STR$ use signed or unsigned runtime formatting according to the expression type.',
        '16-bit words with signed interpretation and wrapping arithmetic':
        '16-bit words with signed unsuffixed and unsigned % interpretation and wrapping arithmetic',
        'Numeric names without a suffix and names ending in % remain distinct namespaces, both holding 16-bit words.':
        'Numeric names without a suffix hold signed 16-bit words; names ending in % hold unsigned 16-bit words (0..65535). They remain distinct namespaces. Arrays and function parameters/results follow their declared suffix. Assignment and parameter/result conversion copy all 16 bits without overflow or range checks.',
        'so multiplication does not require a separate unsigned variable type.':
        'so multiplication shares a bit-level helper; the expression tag determines result interpretation.',
        'unsuffixed numeric variables, division, wrapping arithmetic and signed formatting.':
        'signed unsuffixed and unsigned % variables, mixed signed arithmetic, wrapping and type-directed formatting.',
        'FRE(0) returns the total free user-arena bytes after collection as a 16-bit word. Counts above 32767 display as negative under signed PRINT; the READY banner uses a separate unsigned formatter.':
        'FRE() and compatible FRE(n) collect unreachable objects and coalesce free blocks, then return the total free physical user-arena bytes as an unsigned word. FRE(n) evaluates and ignores its numeric argument. The count includes free-block headers and does not promise a single contiguous allocation. Runtime FRE preserves variables, arrays, source/native code, reservations and CONT; it does not run the destructive stopped CLEAN rebuild. PRINT FRE() therefore displays a positive count even above 32767.',
    })
    rewrites.update({
        'Each numeric value is a 16-bit word.':
        'Each numeric value stores a 16-bit word plus an expression interpretation. Unsuffixed names are signed; % names and FRE results are unsigned. Nonnegative decimal/hex constants, including zero, are unsigned; negative literals are signed, including -32768. Literal magnitudes above 65535 are rejected. Signed interpretation of word u is u below 32768, otherwise u-65536; unsigned interpretation is u. Evaluation follows the expression tree independently of the destination. Assignment and parameter/result conversion preserve all 16 bits without range checks. PRINT 20000+20000 produces 40000, whereas assigning it to A produces -25536 and to A% produces 40000. The integer contract is detailed in docs/integer_arithmetic_design.md; A# fixed point is a future extension.',
        'Division interprets both operand words as signed integers':
        'Binary operations use unsigned interpretation only when both operands are unsigned; mixed operations reinterpret both words as signed. A naked literal adopts the directly combined typed expression interpretation when representable. A computed constant subexpression retains its type; context never changes earlier operations. For U%=40000:B=2, U%/2 is unsigned 20000, U%/B is signed -12768, and with B=-2 it is 12768. Constant-only 4-5 wraps unsigned to 65535; (4-5)/2 is 32767. Addition, subtraction and multiplication retain the low 16 bits at every operation. Signed division truncates toward zero; unsigned division returns the floor quotient. Zero divisors raise ?DIVISION BY ZERO; quotients wrap. Comparisons return signed -1/0. Typed unary minus and NOT preserve type; negative literals are signed. INT and ABS preserve type; signed ABS(-32768) remains -32768. Power requires a nonnegative exponent under the selected interpretation, and x^0 is 1. Explicit arithmetic >> retains sign fill for both word types.',
        'PRINT and STR$ display signed decimal values':
        'PRINT and STR$ select decimal formatting from the expression type: unsigned values print 0..65535, signed values print -32768..32767, using the existing Commodore positive-space/separator conventions. PRINT $D000 displays 53248; V=$D000:PRINT V displays -12288. INPUT and READ copy parsed word bits into the declared target type. VAL still returns a signed word using the shared decimal/hex decoder and longest-prefix policy; malformed hex, oversized magnitudes, fractional and scientific continuations remain rejected.',
        'Signed interpretation still governs comparisons, division, loop limits':
        'Two unsigned operands select unsigned comparisons/division; mixed operations remain signed. FOR limits use the declared loop variable interpretation with signed STEP direction. Byte arguments to POKE, WAIT and CHR$ must be in 0..255 for either numeric type. Subscripts, DIM sizes and allocation counts retain semantic bounds and checked wider products; wrapped numeric arithmetic never permits pointer or allocator overflow. USR still uses its configured vector and word A/X convention.',
        'A nine-byte FOR frame stores':
        'A nine-byte FOR frame stores a tag, scalar cell address, word limit, signed word step and native continuation PC. Unsuffixed and % loop variables are supported; string/subscripted variables are rejected. Initialization/limit/step are evaluated once. NEXT compares using the loop variable interpretation, with signed STEP direction. Unsigned NEXT detects wrap or underflow so loops ending at 65535 or zero terminate. Existing signed boundary wrap and STEP-zero nontermination remain; polling stays active.',
    })
    # Also recognize paragraphs produced by earlier synchronizations.
    rewrites['Each numeric value stores a 16-bit word'] = rewrites['Each numeric value is a 16-bit word.']
    rewrites['Binary operations use unsigned interpretation'] = rewrites['Division interprets both operand words as signed integers']
    rewrites['PRINT and STR$ select decimal formatting'] = rewrites['PRINT and STR$ display signed decimal values']
    rewrites['LIST traverses the live trailer chain'] = (
        'LIST traverses the live trailer chain, prints decimal line numbers and expands tokens '
        'with canonical spacing. Calls and array/DEF FN argument lists attach the opening '
        'parenthesis to the name; opening/closing delimiters have no interior padding. Keep '
        'spaces around assignment/arithmetic/comparison/logical operators, so TAB ( 11 ) '
        'becomes TAB(11), CHR$ (147) becomes CHR$(147), and X=(1+2)*3 becomes X = (1 + 2) * 3. '
        'No gap precedes comma/semicolon; ordinary separators remain between arguments and '
        'statements. Expand keyword abbreviations and preserve complete identifier spelling. '
        'String, REM and DATA payload bytes are preserved; signed DATA values keep their sign '
        'attached. Decimal immediates retain unsigned source magnitude and hex prints $ plus '
        'four uppercase digits. PRINT/STR$ still use expression-directed runtime formatting. '
        'Both target/host tokenizers accept whitespace before TAB/SPC opening parentheses.')
    rewrites['SAVE writes Assembly BASIC source format version 1'] = (
        'SAVE writes Assembly BASIC source format version 1, specified in Appendix A. The '
        'container has magic/version, names, sorted line/token records and CRC; it has no '
        'pointers, native bodies, anchors or C64 load address. SAVE, LOAD and VERIFY accept '
        'filename[,device[,secondary]], defaulting device to 8. The optional secondary is '
        'evaluated once and checked as a byte 0..255, then ignored for source-only .AB files. '
        'Use a Commodore sequential byte file; transport retains channel 2 regardless of '
        'the compatibility argument. Validate the complete argument list before emitting '
        'the file operation, so malformed file arguments cannot write/load first and raise a '
        'syntax trap afterward. Colon and ELSE are legitimate boundaries. LOAD keeps its '
        'existing staged publication and return-to-READY behavior.')
    rewrites.update({
        'Use a seven-byte stable anchor per line':
        'Use a seven-byte stable anchor per line and a single allocation containing its tokens and native body. Bind full identifiers to an interned name dictionary. Keywords, operators and the first 128 name references each occupy one byte; valid integer immediates are binary values. Runtime calls use fixed RAM helpers or common-RAM service entry stubs. Cold DATA/READ/RESTORE, DEF FN activation and device/input helpers execute from bank-2 ROM through bank_call; hot arithmetic, arrays, strings, function calls and collection remain in RAM.',
        'Emit documented NMOS 6502 machine code immediately after tokenization':
        'Emit documented NMOS 6502 machine code immediately after tokenization; share hot semantics through copied RAM helpers and cold services through common-RAM banked ROM calls.',
        'Every map-changing instruction sequence executes':
        'Every map-changing instruction sequence executes from common RAM. bank_call uses four inline descriptor bytes after JSR: bank (0..7 or $FF to retain current), port low bits (5 or 7), then a little-endian target word. It reads the descriptor in the caller map, advances the return address past it and saves full $01, bank and caller P on a per-call hardware-stack frame. Setup and return mask IRQs; the callee receives A/X/Y and the caller interrupt mask with D clear. Return yields A/X/Y and callee N/Z/C/V, restores full $01, bank and caller I, and clears D. Active calls add five stack bytes beyond an ordinary JSR, plus temporary dispatch and helper locals. Targets/returns are stacked before IRQ enable; nested calls safely reuse setup scratch. ROM code enters common RAM before changing banks/maps. read_ram handles shadow source reads, and RAM_CALL descriptors reach hot helpers with the current bank and map 5. KERNAL, command-to-RAM, source-file and image-copy gateways share bank_call; copies retain their fully masked IRQ and saved-flags contract. SYS/USR retain their own return conventions.',
        'RAM helpers call SETNAM':
        'Resident and banked helpers call SETNAM, SETLFS, OPEN, CLOSE, CHKIN, CHKOUT, CLRCHN, CHRIN, CHROUT, GETIN, READST, RDTIM and SETTIM through the common kernal_gate/bank_call ABI. Restore caller mapping/bank and documented results. Stage arguments originally under ROM into common buffers. Blocking input permits IRQs and resumes its nested bank frames. Nonreturning errors establish bank 0 through RAM error/READY recovery and reset the hardware stack. DEF FN activation consumes its original native return address in a RAM stub and reads the four inline operands through read_ram; hot FN calls remain in RAM.',
        'Serial source files are streamed as bounded chunks through common RAM.':
        'Serial source files are streamed as bounded chunks through common RAM. Do not call unrestricted KERNAL LOAD into the arena: it could overwrite source/code, gateways or resident helpers. The ROM file wrapper enters bank-0 source transport through bank_call. KERNAL-owned state stays excluded from the arena. $0334-$03FF holds 152 bytes of service/output stubs and 52 bytes of editor state; $0A60-$0AFF holds the 160-byte editor draft. The keyboard-input stub shares the main gateway code span. Install contents after KERNAL initialization because RAMTAS clears page 3; preserve vectors through $0333 and keep tape transport unsupported.',
        'KERNAL gateways save low mapping bits':
        'KERNAL gateways use bank_call to save the complete $01, interrupt state and bank shadow on each call frame. Expose I/O before selecting bank 0, preserve service arguments/results and carry, and restore the bank before the original complete map. Image copies reuse the ABI with IRQs masked throughout the copy and restore original flags. Every bank-selection instruction and its return path executes in common RAM. NMI stays in common RAM and leaves the bank and dispatch scratch unchanged.',
        'The seven-byte anchor and binary vocabulary are defined designs':
        'The seven-byte anchor and binary vocabulary are defined designs with development measurements recorded in Appendix B. Release evidence must cover the resident helper closure within 7162 bytes, the main gateway within 768 bytes, service entry stubs within 204 bytes, ROM-service dependency/access contracts, nested bank and interrupt restoration, and source-preserving rebuilds. Explicit banked services may execute in ROM through the published ABI while native code and hot helpers retain the RAM execution map. Resolve budget or acceptance failures explicitly; retain custom source tokens and validate every RAM/ROM transition.',
    })
    paragraphs=list(body.iter(f'{{{W}}}p'))
    for p in paragraphs:
        nodes=list(p.iter(f'{{{W}}}t'))
        if not nodes:continue
        value=''.join(n.text or '' for n in nodes)
        revised=value
        for a,b in replacements.items():revised=revised.replace(a,b)
        for prefix,text in rewrites.items():
            if revised.startswith(prefix):revised=text;break
        if revised!=value:
            nodes[0].text=revised
            for n in nodes[1:]:n.text=''
    status_line=('Implementation status: working development cartridge; the full version-one '
                 'release is not complete. See Appendix B for measured implementation '
                 'facts, explicit differences and pending acceptance work.')
    if not any(''.join(p.itertext()).startswith('Implementation status:') for p in body):
        body.insert(2,paragraph(status_line))
    def set_cell(cell, text):
        nodes=list(cell.iter(f'{{{W}}}t'))
        nodes[0].text=text
        for node in nodes[1:]:node.text=''
    for table in root.findall('.//w:tbl',NS):
        for row in list(table.findall('w:tr',NS)):
            cells=row.findall('w:tc',NS)
            values=[''.join(c.itertext()) for c in cells]
            if values[0]=='$0200-$03FF':
                for c,text in zip(cells,('$0200-$0333','308 bytes','KERNAL state, RAM vectors and input buffers; preserve ownership.')):set_cell(c,text)
                new=copy.deepcopy(row)
                for c,text in zip(new.findall('w:tc',NS),('$0334-$03FF','204 bytes','Reserved, currently unassigned common RAM for future firmware code, data or workspace. Tape buffer reclaimed while tape transport is unsupported. Bank gateways are prospective; other uses remain open. Install future contents after KERNAL initialization (RAMTAS clears page 3).')):set_cell(c,text)
                table.insert(list(table).index(row)+1,new)
            elif values[0]=='$1400-$7FFF':
                for c,text in zip(cells,('$1400-$2BFF','6 KB','Resident compiler, copied from bank 1 at cold start; excluded from user allocation.')):set_cell(c,text)
                new=copy.deepcopy(row)
                for c,text in zip(new.findall('w:tc',NS),('$2C00-$7FFF','21 KB','Common user arena; stable anchors, names and bindings allocate here.')):set_cell(c,text)
                table.insert(list(table).index(row)+1,new)
            elif values[0]=='$1A-$1F':
                for c,text in zip(cells,('$1A-$1B','Arithmetic shift operators << and >>','1 byte')):set_cell(c,text)
                new=copy.deepcopy(row)
                for c,text in zip(new.findall('w:tc',NS),('$1C-$1F','Reserved; reject in format version 1','No valid encoding')):set_cell(c,text)
                table.insert(list(table).index(row)+1,new)
            elif values[0] in ('$20-$67', '$20-$69'):set_cell(cells[0],'$20-$6A')
            elif values[0] in ('$68-$6F', '$6A-$6F'):set_cell(cells[0],'$6B-$6F')
        rows=table.findall('w:tr',NS)
        header=''.join(rows[0].itertext())
        contents=''.join(table.itertext())
        if header.startswith('Cartridge contents'):
            template=copy.deepcopy(rows[-1])
            for old in rows[1:]:table.remove(old)
            set_cell(rows[0].findall('w:tc',NS)[1],'Bank budget / measured used bytes')
            for bank in report['banks']:
                new=copy.deepcopy(template)
                for c,text in zip(new.findall('w:tc',NS),
                                  (f"Bank {bank['bank']}: {bank['role']}",
                                   f"8192 / {bank['used_bytes']} bytes")):set_cell(c,text)
                table.append(new)
            new=copy.deepcopy(template)
            for c,text in zip(new.findall('w:tc',NS),('Hard cartridge limit','64 KiB (65536 bytes)')):set_cell(c,text)
            table.append(new)
        if 'Punctuation or operator' in header and '$1A' not in contents:
            new=copy.deepcopy(rows[-1])
            for c,text in zip(new.findall('w:tc',NS),('$1A','<<','$1B','>>')):set_cell(c,text)
            table.append(new)
        if header=='CodeKeywordCodeKeyword' and '$68' not in contents:
            new=copy.deepcopy(rows[-1])
            for c,text in zip(new.findall('w:tc',NS),('$68','ELSE','$69','CLEAN')):set_cell(c,text)
            table.append(new)
        if header=='CodeKeywordCodeKeyword' and 'RESERVE' not in contents:
            new=copy.deepcopy(rows[-1])
            for c,text in zip(new.findall('w:tc',NS),('$6A','RESERVE','','')):set_cell(c,text)
            table.append(new)
    for row in root.findall('.//w:tr',NS):
        cells=row.findall('w:tc',NS)
        if len(cells)<2:continue
        address=''.join(n.text or '' for n in cells[0].iter(f'{{{W}}}t'))
        if address=='$E000-$E3FF':
            ts=list(cells[1].iter(f'{{{W}}}t'));ts[0].text='1 KB RAM'
            for t in ts[1:]:t.text=''
        elif address=='$1400-$2BFF':
            set_cell(cells[-1],'Resident compiler, copied from bank 1 at cold start; excluded from user allocation.')
        elif address=='$0334-$03FF':
            set_cell(cells[-1],f"Firmware-owned common RAM: {report['service_gateway_used_bytes']} bytes of banked-service/output entry stubs, copied after KERNAL initialization (RAMTAS clears page 3); {204-report['service_gateway_used_bytes']} bytes hold editor state at $03CC-$03FF. Tape transport stays unsupported.")
        elif address=='$8000-$BFFF':
            set_cell(cells[-1],'User tokens, native bodies, arrays and strings beneath cartridge/BASIC ROM; common bindings remain below $8000.')
    marker='Appendix B — implementation status, revision 0.12'
    additions=[paragraph(marker,True),paragraph(
        'This appendix records the development implementation on 14 October 2026. '
        'The full version-one contract is not yet complete. Original release '
        'requirements above remain the target unless an architectural choice is '
        'explicitly revised here. Original revision 0.3 is preserved in Git commit 9480026.'),
        paragraph('Measured linked build: '+json.dumps(report,sort_keys=True)),
        paragraph(f"Automated validation: {tests['tests_run']} tests passed, "
                  f"{tests['runtime_instructions_checked']} documented runtime instructions checked. "
                  'Environment: instruction-level py65 with deterministic KERNAL stubs; '
                  'this is not cycle-accurate or physical-machine acceptance evidence.'),
        paragraph('Source/container version 1 and runtime ABI 7 are distinct. '
                  'Language zero page is $02-$78; common workspace is $0800-$13FF. '
                  'Function activations currently use a guarded hardware stack with depth eight. '
                  'The compiler emits native helper calls and branches, with literal power-of-two multiplication/division lowered to dedicated arithmetic shift helpers. Signed division applies a negative-operand bias to preserve truncation toward zero; unsigned division uses zero-fill shifts. Literal $8000 is unsigned 32768, becoming signed -32768 only in mixed division. Strength reduction preserves the type and wrapping of every operation; there is no general constant folder. General inline scalar optimizations remain pending. The compiler reservation is $1400-$2BFF and the arena begins at $2C00.')]
    measurements=json.loads((ROOT/'docs/measurements.json').read_text())
    assert measurements['rom_sha256']==report['rom_sha256'], 'Measurements refer to a different cartridge'
    additions.append(paragraph('Instruction-level measurements and capacity scenario: '+
                               json.dumps(measurements,sort_keys=True)))
    collection=json.loads((ROOT/'docs/voidrunner-collection.json').read_text())
    assert collection['rom_sha256']==report['rom_sha256'], 'Collection measurements refer to a different cartridge'
    additions.append(paragraph('Captured Void Runner collection replay: '+json.dumps(collection,sort_keys=True)))
    status=(ROOT/'docs/IMPLEMENTATION_STATUS.md').read_text()+'\n'+(ROOT/'docs/MAGIC_DESK_BANKS.md').read_text()+'\n'+(ROOT/'docs/SCREEN_EDITOR.md').read_text()+'\n'+(ROOT/'docs/integer_arithmetic_design.md').read_text(encoding='utf-8-sig')
    for line in status.splitlines():
        if not line or line.startswith('| ---'):continue
        if line.startswith('#'):additions.append(paragraph(line.lstrip('# '),True))
        elif line.startswith('|'):
            fields=[f.strip() for f in line.strip('|').split('|')]
            additions.append(paragraph(' — '.join(fields)))
        else:additions.append(paragraph(line.lstrip('- ')))
    section=body.find('w:sectPr',NS)
    position=list(body).index(section) if section is not None else len(body)
    for p in additions:body.insert(position,p);position+=1
    xml=serialize(root,declared)
    temporary=DOC.with_suffix('.docx.tmp')
    with zipfile.ZipFile(temporary,'w') as z:
        for info,data in entries:
            if info.filename=='word/document.xml':data=xml
            elif info.filename=='docProps/core.xml':
                core_namespaces=namespaces(data)
                core=ET.fromstring(data)
                for n in core:
                    if n.tag.endswith('}revision'):n.text='12'
                    if n.tag.endswith('}modified'):n.text='2026-10-14T00:00:00Z'
                data=serialize(core,core_namespaces)
            z.writestr(info,data)
    with zipfile.ZipFile(temporary) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if name.endswith('.xml'):ET.fromstring(z.read(name))
    assert hashlib.sha256(DOC.read_bytes()).hexdigest()==design_before, 'Design document changed during synchronization; preserve the user edit and rerun'
    temporary.replace(DOC)
    text='\n'.join(''.join(n.text or '' for n in p.iter(f'{{{W}}}t'))
                   for p in root.iter(f'{{{W}}}p'))+'\n'
    (ROOT/'docs/Assembly_BASIC_C64_Design.txt').write_text(text)
    (ROOT/'docs/design-sync.json').write_text(json.dumps({
        'design_revision':'0.12','runtime_abi':report['runtime_abi'],
        'design_sha256':hashlib.sha256(DOC.read_bytes()).hexdigest(),
        'rom_sha256':report['rom_sha256'],'runtime_run_address':report['runtime_run_address'],
        'arena_raw_bytes':report['arena_raw_bytes'],
        'compiler_run_address':report['compiler_run_address'],
        'compiler_budget_bytes':report['compiler_budget_bytes']},indent=2)+'\n')
    print('Updated design revision 0.12 and readable export; original revision remains in Git.')

if __name__=='__main__':synchronize()
