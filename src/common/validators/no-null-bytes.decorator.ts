import { ValidateBy } from 'class-validator';

const NULL_BYTE = String.fromCharCode(0);

/**
 * Rejects strings containing the NUL character.
 *
 * PostgreSQL text columns cannot store it, so it made the database throw
 * and the API answer 500 instead of 400. Found by the OWASP ZAP scan
 * (step 9), which sends "%00" in every parameter.
 */
export function NoNullBytes(): PropertyDecorator {
  return ValidateBy({
    name: 'noNullBytes',
    validator: {
      validate: (value) =>
        typeof value !== 'string' || !value.includes(NULL_BYTE),
      defaultMessage: () => '$property must not contain null bytes',
    },
  });
}
