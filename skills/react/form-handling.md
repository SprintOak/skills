# React Form Handling

## Stack

- **React Hook Form (RHF)** — form state, validation, submission
- **Zod** — schema definition and type inference
- **@hookform/resolvers** — bridge between RHF and Zod

```bash
npm install react-hook-form zod @hookform/resolvers
```

DO: Always use React Hook Form for any form with more than one field.
DON'T: Use uncontrolled forms, manual `useState` for form fields, or custom form validation logic.

---

## Core Pattern: Schema → Type → Form

Always follow this sequence:

1. Define the Zod schema
2. Infer the TypeScript type from it
3. Pass the type to `useForm` and use `zodResolver`

```tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

// 1. Define schema
const loginSchema = z.object({
  email: z.string().email('Enter a valid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

// 2. Infer type
type LoginFormValues = z.infer<typeof loginSchema>;

// 3. Use in component
function LoginForm() {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      email: '',
      password: '',
    },
  });

  const onSubmit = async (data: LoginFormValues) => {
    await loginUser(data);
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <div>
        <label htmlFor="email">Email</label>
        <input
          id="email"
          type="email"
          aria-invalid={!!errors.email}
          aria-describedby={errors.email ? 'email-error' : undefined}
          {...register('email')}
        />
        {errors.email && (
          <p id="email-error" role="alert">{errors.email.message}</p>
        )}
      </div>

      <div>
        <label htmlFor="password">Password</label>
        <input
          id="password"
          type="password"
          aria-invalid={!!errors.password}
          aria-describedby={errors.password ? 'password-error' : undefined}
          {...register('password')}
        />
        {errors.password && (
          <p id="password-error" role="alert">{errors.password.message}</p>
        )}
      </div>

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Logging in…' : 'Log in'}
      </button>
    </form>
  );
}
```

---

## register vs Controller

**`register`** — use for native HTML inputs (text, email, password, number, textarea, select, checkbox, radio).

```tsx
<input {...register('email')} />
<textarea {...register('bio')} />
<select {...register('country')}>
  <option value="us">United States</option>
</select>
```

**`Controller`** — use for custom components or UI library components that do not expose a native `ref` or do not follow standard DOM event patterns.

```tsx
import { Controller } from 'react-hook-form';
import { DatePicker } from '@acme/ui';

<Controller
  name="birthDate"
  control={control}
  render={({ field, fieldState }) => (
    <DatePicker
      value={field.value}
      onChange={field.onChange}
      onBlur={field.onBlur}
      error={fieldState.error?.message}
    />
  )}
/>
```

DON'T: Wrap native inputs in `Controller` — use `register` instead (more performant).

---

## FormField Component Pattern

Create a reusable `FormField` wrapper to avoid repeating label + error + aria wiring.

```tsx
// components/FormField.tsx
import { useFormContext } from 'react-hook-form';

interface FormFieldProps {
  name: string;
  label: string;
  children: (props: {
    id: string;
    'aria-invalid': boolean;
    'aria-describedby'?: string;
  }) => React.ReactNode;
}

function FormField({ name, label, children }: FormFieldProps) {
  const { formState: { errors } } = useFormContext();
  const error = errors[name];
  const errorId = `${name}-error`;

  return (
    <div className="form-field">
      <label htmlFor={name}>{label}</label>
      {children({
        id: name,
        'aria-invalid': !!error,
        'aria-describedby': error ? errorId : undefined,
      })}
      {error?.message && (
        <p id={errorId} role="alert" className="form-field__error">
          {String(error.message)}
        </p>
      )}
    </div>
  );
}

// Usage
function ProfileForm() {
  const methods = useForm<ProfileValues>({ resolver: zodResolver(profileSchema) });

  return (
    <FormProvider {...methods}>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        <FormField name="username" label="Username">
          {(props) => <input {...props} {...methods.register('username')} />}
        </FormField>
      </form>
    </FormProvider>
  );
}
```

---

## Error Display

Always display error messages at the field level. Use `formState.errors` — never build your own error state.

```tsx
// Field-level errors from Zod
const { formState: { errors } } = useForm();

// Access nested errors
errors.address?.street?.message
errors.tags?.[0]?.message

// Display pattern
{errors.email && (
  <p id="email-error" role="alert" className="error-message">
    {errors.email.message}
  </p>
)}
```

For form-level errors (e.g., API errors), use `setError`:

```tsx
const onSubmit = async (data: FormValues) => {
  try {
    await submitForm(data);
  } catch (err) {
    setError('root', {
      type: 'server',
      message: 'Submission failed. Please try again.',
    });
  }
};

// Render root error
{errors.root && (
  <div role="alert" className="form-error-banner">
    {errors.root.message}
  </div>
)}
```

---

## Watch and Trigger

Use `watch` to reactively read field values. Use `trigger` to manually run validation.

```tsx
const { watch, trigger } = useForm<FormValues>();

// Watch a single field
const country = watch('country');

// Watch multiple fields
const [firstName, lastName] = watch(['firstName', 'lastName']);

// Conditionally render based on watched value
{country === 'US' && (
  <input {...register('state')} placeholder="State" />
)}

// Manually trigger validation (e.g., after an async check)
const handleEmailBlur = async () => {
  await trigger('email');
};
```

DON'T: Use `watch` on the entire form object in performance-sensitive components — it re-renders on every keystroke.

---

## Dynamic Fields with useFieldArray

```tsx
import { useFieldArray } from 'react-hook-form';

const phoneSchema = z.object({
  phones: z.array(
    z.object({
      number: z.string().min(10, 'Enter a valid phone number'),
      label: z.string(),
    })
  ).min(1, 'Add at least one phone number'),
});

type PhoneFormValues = z.infer<typeof phoneSchema>;

function PhoneForm() {
  const { control, register, handleSubmit, formState: { errors } } = useForm<PhoneFormValues>({
    resolver: zodResolver(phoneSchema),
    defaultValues: { phones: [{ number: '', label: 'mobile' }] },
  });

  const { fields, append, remove } = useFieldArray({
    control,
    name: 'phones',
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      {fields.map((field, index) => (
        <div key={field.id}>  {/* Always use field.id, never index */}
          <input
            {...register(`phones.${index}.number`)}
            placeholder="Phone number"
            aria-label={`Phone number ${index + 1}`}
          />
          {errors.phones?.[index]?.number && (
            <p role="alert">{errors.phones[index].number.message}</p>
          )}
          <button type="button" onClick={() => remove(index)}>Remove</button>
        </div>
      ))}
      <button type="button" onClick={() => append({ number: '', label: 'mobile' })}>
        Add phone
      </button>
      <button type="submit">Save</button>
    </form>
  );
}
```

DON'T: Use the array index as `key` in `useFieldArray` — always use `field.id`.

---

## Nested Object Fields

```tsx
const addressSchema = z.object({
  address: z.object({
    street: z.string().min(1, 'Street is required'),
    city: z.string().min(1, 'City is required'),
    zip: z.string().regex(/^\d{5}$/, 'Enter a 5-digit ZIP code'),
  }),
});

// Register with dot notation
<input {...register('address.street')} />
<input {...register('address.city')} />
<input {...register('address.zip')} />

// Access nested errors
errors.address?.street?.message
```

---

## Form Reset After Successful Submit

```tsx
const { reset, handleSubmit } = useForm<FormValues>({
  defaultValues: { title: '', body: '' },
});

const onSubmit = async (data: FormValues) => {
  await createPost(data);
  reset(); // Reset to defaultValues

  // Or reset to specific values
  reset({ title: '', body: '' });
};
```

---

## Loading State During Submission

Use `formState.isSubmitting` — it is automatically `true` while the async `onSubmit` handler is running.

```tsx
const { formState: { isSubmitting } } = useForm();

<button type="submit" disabled={isSubmitting}>
  {isSubmitting ? <Spinner /> : 'Submit'}
</button>

// Also disable inputs during submission to prevent edits
<input {...register('email')} disabled={isSubmitting} />
```

DON'T: Create separate `useState` for loading state when `isSubmitting` already handles it.

---

## Reusable Form Field Components

```tsx
// components/TextInput.tsx
import { useFormContext } from 'react-hook-form';

interface TextInputProps {
  name: string;
  label: string;
  type?: string;
  placeholder?: string;
}

function TextInput({ name, label, type = 'text', placeholder }: TextInputProps) {
  const { register, formState: { errors } } = useFormContext();
  const error = errors[name];
  const errorId = `${name}-error`;

  return (
    <div>
      <label htmlFor={name}>{label}</label>
      <input
        id={name}
        type={type}
        placeholder={placeholder}
        aria-invalid={!!error}
        aria-describedby={error ? errorId : undefined}
        {...register(name)}
      />
      {error?.message && (
        <p id={errorId} role="alert">{String(error.message)}</p>
      )}
    </div>
  );
}
```

Use `FormProvider` at the parent so field components can access form context via `useFormContext`.

---

## Multi-Step Form Pattern

```tsx
const STEPS = ['personal', 'address', 'review'] as const;
type Step = typeof STEPS[number];

function MultiStepForm() {
  const [currentStep, setCurrentStep] = useState<Step>('personal');
  const methods = useForm<FullFormValues>({
    resolver: zodResolver(fullFormSchema),
    mode: 'onTouched',
  });

  const goToNext = async () => {
    const fieldsForStep: Record<Step, (keyof FullFormValues)[]> = {
      personal: ['firstName', 'lastName', 'email'],
      address: ['street', 'city', 'zip'],
      review: [],
    };

    const valid = await methods.trigger(fieldsForStep[currentStep]);
    if (valid) {
      const nextIndex = STEPS.indexOf(currentStep) + 1;
      setCurrentStep(STEPS[nextIndex]);
    }
  };

  return (
    <FormProvider {...methods}>
      <form onSubmit={methods.handleSubmit(onSubmit)}>
        {currentStep === 'personal' && <PersonalStep />}
        {currentStep === 'address' && <AddressStep />}
        {currentStep === 'review' && <ReviewStep />}

        {currentStep !== 'review' && (
          <button type="button" onClick={goToNext}>Next</button>
        )}
        {currentStep === 'review' && (
          <button type="submit">Submit</button>
        )}
      </form>
    </FormProvider>
  );
}
```

---

## Async Validation

Use Zod's `.refine()` or `.superRefine()` with async functions for server-side validation.

```tsx
const usernameSchema = z.object({
  username: z
    .string()
    .min(3, 'Username must be at least 3 characters')
    .refine(
      async (value) => {
        const { available } = await checkUsernameAvailability(value);
        return available;
      },
      { message: 'This username is already taken' }
    ),
});

// Enable async validation in RHF
const form = useForm({
  resolver: zodResolver(usernameSchema),
  mode: 'onBlur', // validate on blur to avoid calling API on every keystroke
});
```

---

## Conditional Fields

```tsx
const schema = z.discriminatedUnion('contactMethod', [
  z.object({ contactMethod: z.literal('email'), email: z.string().email() }),
  z.object({ contactMethod: z.literal('phone'), phone: z.string().min(10) }),
]);

function ContactForm() {
  const { register, watch, formState: { errors } } = useForm({
    resolver: zodResolver(schema),
    defaultValues: { contactMethod: 'email' },
  });

  const contactMethod = watch('contactMethod');

  return (
    <form>
      <select {...register('contactMethod')}>
        <option value="email">Email</option>
        <option value="phone">Phone</option>
      </select>

      {contactMethod === 'email' && (
        <input {...register('email')} type="email" placeholder="Email address" />
      )}
      {contactMethod === 'phone' && (
        <input {...register('phone')} type="tel" placeholder="Phone number" />
      )}
    </form>
  );
}
```

---

## File Upload Handling

```tsx
const uploadSchema = z.object({
  avatar: z
    .instanceof(FileList)
    .refine((files) => files.length > 0, 'Please select a file')
    .refine((files) => files[0]?.size <= 2 * 1024 * 1024, 'File must be under 2MB')
    .refine(
      (files) => ['image/jpeg', 'image/png', 'image/webp'].includes(files[0]?.type),
      'Only JPEG, PNG, and WebP are allowed'
    ),
});

function AvatarUploadForm() {
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(uploadSchema),
  });

  const onSubmit = async (data: { avatar: FileList }) => {
    const formData = new FormData();
    formData.append('avatar', data.avatar[0]);
    await uploadAvatar(formData);
  };

  return (
    <form onSubmit={handleSubmit(onSubmit)} encType="multipart/form-data">
      <label htmlFor="avatar">Profile picture</label>
      <input
        id="avatar"
        type="file"
        accept="image/jpeg,image/png,image/webp"
        aria-invalid={!!errors.avatar}
        aria-describedby={errors.avatar ? 'avatar-error' : undefined}
        {...register('avatar')}
      />
      {errors.avatar && (
        <p id="avatar-error" role="alert">{errors.avatar.message}</p>
      )}
      <button type="submit">Upload</button>
    </form>
  );
}
```

---

## Form Accessibility Checklist

- Every input has a visible `<label>` with `htmlFor` matching the input `id`
- Error messages use `role="alert"` so screen readers announce them
- Inputs have `aria-invalid="true"` when they contain an error
- Inputs have `aria-describedby` pointing to the error message element id
- Submit buttons show loading state and are disabled during submission
- The `<form>` element has `noValidate` when using custom validation (prevents browser native tooltip errors)

```tsx
// Complete accessible field pattern
<div>
  <label htmlFor="email">Email address</label>
  <input
    id="email"
    type="email"
    autoComplete="email"
    aria-required="true"
    aria-invalid={!!errors.email}
    aria-describedby={errors.email ? 'email-error' : 'email-hint'}
    {...register('email')}
  />
  <p id="email-hint" className="hint">We'll never share your email.</p>
  {errors.email && (
    <p id="email-error" role="alert" className="error">{errors.email.message}</p>
  )}
</div>
```
