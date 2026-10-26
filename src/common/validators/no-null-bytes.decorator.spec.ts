import { validate } from 'class-validator';
import { NoNullBytes } from './no-null-bytes.decorator';

class Sample {
  @NoNullBytes()
  value: string;
}

describe('NoNullBytes', () => {
  const errorsFor = async (value: string) => {
    const sample = new Sample();
    sample.value = value;
    return validate(sample);
  };

  it('accepts normal text', async () => {
    expect(await errorsFor('hello world')).toHaveLength(0);
  });

  it('rejects a string with a null byte', async () => {
    expect(await errorsFor(`abc${String.fromCharCode(0)}def`)).toHaveLength(1);
  });
});
