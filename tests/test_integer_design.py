"""Public integer specification examples and optimized/generic agreement."""
import random
import unittest
from machine import Machine
from ab64.container import dumps
from ab64.tokens import Names, tokenize


def signed(word):
    return (word + 32768) % 65536 - 32768


class IntegerDesignTests(unittest.TestCase):
    def setUp(self):
        self.m = Machine().boot()

    def number(self, expression):
        output = self.m.command('PRINT ' + expression)
        self.assertNotIn('?', output, expression)
        return int(output.split('\r')[0])

    def test_specification_constants_and_destinations(self):
        for expression, expected in {
            '20000+20000': 40000, '4-5': 65535, '-5+4': -1,
            '(4-5)/2': 32767, '(65535+1)/2': 0,
            '(20000+20000)/2': 20000, '-32768': -32768,
            '-32768/-1': -32768, '-32768/2': -16384,
            '(65535*65535)/2': 0, '(32768+32768)-1': 65535,
            '-2^2': -4, '-(2*2)': 65532, '-(4-5)': 1,
            '-(2^2)': 65532, '-(2)': -2, '-(32768)': -32768,
            '($FFFF-4)/2': 32765, '65535<0': 0,
            '65535>-1': 0, 'NOT 1': 65534,
        }.items():
            self.assertEqual(self.number(expression), expected, expression)
        self.assertEqual(self.m.command(
            'A=20000+20000:A%=20000+20000:B%=-5+4:PRINT A;A%;B%'
        ).split('\r')[0], '-25536  40000  65535 ')
        self.m.command('U%=65535:A=U%:B%=A')
        self.assertEqual(self.number('A'), -1)
        self.assertEqual(self.number('B%'), 65535)

    def test_literal_context_is_local_and_destination_independent(self):
        self.m.command('U%=40000:B=2:N=-2')
        for expression, expected in {
            'U%/2': 20000, 'U%/(2)': 20000, 'U%/B': -12768,
            'U%/(2+0)': 20000, 'U%/(B+0)': -12768,
            'U%/2+B': 20002, 'U%+B+2': -25532,
            '(U%+B)/2': -12767, 'U%+(-2)': -25538,
            'N+40000': -25538, 'U%+(4-5)': 39999,
            'N+(4-5)': -3, '(4-5)/B': 0, 'N/2': -1,
            '2/N': -1, '-32768/U%': 1,
        }.items():
            self.assertEqual(self.number(expression), expected, expression)
        self.m.command('B=-2')
        self.assertEqual(self.number('U%/B'), 12768)
        self.m.command('A=U%/2:A%=U%/2')
        self.assertEqual(self.number('A'), 20000)
        self.assertEqual(self.number('A%'), 20000)

    def test_declared_values_and_functions_do_not_become_constant_literals(self):
        self.m.command('DIM U%(0):U%(0)=65535:DEF FN F%(X%)=X%')
        for expression, expected in {
            'U%(0)/2': 32767, '-U%(0)': 1,
            '-(2*U%(0))': 2, '-FN F%(2)': 65534,
            '-ABS(2)': 65534, '-INT(2)': 65534,
            'SGN(65535)': 1, 'SGN(-1)': -1,
        }.items():
            self.assertEqual(self.number(expression), expected, expression)
        self.assertIn('?DIVISION BY ZERO', self.m.command('PRINT 1/(65535+1)'))

    def test_unsigned_literals_do_not_change_poke_address_bits(self):
        self.m.command('POKE 53280,6:A=53280:POKE A,7')
        self.assertEqual(self.m.memory.ram[53280], 7)

    def test_power_lowering_matches_generic_typed_arithmetic(self):
        rng = random.Random(1616)
        words = [0, 1, 32767, 32768, 32769, 65534, 65535]
        words += [rng.randrange(65536) for _ in range(9)]
        for bits in words:
            self.m.command(f'S={bits}:U%={bits}')
            for exponent in (0, 1, 4, 8, 14, 15):
                divisor = 1 << exponent
                self.m.command(f'D%={divisor}')
                for name, value, unsigned in (
                    ('S', signed(bits), False), ('U%', bits, True)
                ):
                    effective_divisor = divisor if unsigned else signed(divisor)
                    quotient = abs(value) // abs(effective_divisor)
                    if (value < 0) != (effective_divisor < 0):
                        quotient = -quotient
                    quotient = quotient & 65535 if unsigned else signed(quotient)
                    product = (bits * divisor) & 65535
                    if not unsigned:
                        product = signed(product)
                    for literal in (str(divisor), f'(${divisor:X})'):
                        self.assertEqual(self.number(f'{name}/{literal}'), quotient)
                        self.assertEqual(self.number(f'{name}*{literal}'), product)
                        self.assertEqual(self.number(f'{literal}*{name}'), product)
                    self.assertEqual(self.number(f'{name}/D%'), quotient)
                    self.assertEqual(self.number(f'{name}*D%'), product)
        for source, expected in {'65535/32768': 1, '65535*32768': 32768,
                                 '32768*65535': 32768, '-32768/32768': 1}.items():
            self.assertEqual(self.number(source), expected)

    def test_saved_and_cleaned_source_recompiles_with_new_types(self):
        names = Names()
        lines = {10: tokenize('U%=40000:B=2:PRINT U%/2;U%/B;(4-5)/2;-32768', names)}
        self.m.files['INTEGER'] = bytearray(dumps(names, lines))
        self.assertNotIn('?', self.m.command('LOAD "INTEGER",8,1'))
        expected = ' 20000 -12768  32767 -32768 '
        self.assertEqual(self.m.command('RUN').split('\r')[0], expected)
        self.assertNotIn('?', self.m.command('CLEAN'))
        self.assertEqual(self.m.command('RUN').split('\r')[0], expected)
