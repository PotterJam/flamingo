import type { PolymorphicProps } from '@kobalte/core/polymorphic';
import type { ValidComponent } from 'solid-js';

import { splitProps } from 'solid-js';
import * as SeparatorPrimitive from '@kobalte/core/separator';

import { cn } from '../../lib/utils/cn';

type SeparatorRootProps<T extends ValidComponent = 'hr'> =
    SeparatorPrimitive.SeparatorRootProps<T> & { class?: string | undefined };

const Separator = <T extends ValidComponent = 'hr'>(
    props: PolymorphicProps<T, SeparatorRootProps<T>>
) => {
    const [local, others] = splitProps(props as SeparatorRootProps, [
        'class',
        'orientation',
    ]);
    return (
        <SeparatorPrimitive.Root
            data-slot="separator"
            orientation={local.orientation ?? 'horizontal'}
            class={cn(
                'bg-muted-foreground shrink-0',
                local.orientation === 'vertical'
                    ? 'h-full w-0.5'
                    : 'h-0.5 w-full',
                local.class
            )}
            {...others}
        />
    );
};

export { Separator };
