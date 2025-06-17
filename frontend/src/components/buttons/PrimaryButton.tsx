import { JSX } from 'solid-js';
import { twMerge } from 'tailwind-merge';

interface PrimaryButtonProps {
    onClick?: () => void;
    disabled?: boolean;
    children: JSX.Element;
    type?: string;
    class?: string;
}

export const PrimaryButton = (props: PrimaryButtonProps) => {
    const enabledStyles =
        'w-full rounded bg-pink-400 px-4 py-2 font-bold text-white hover:bg-pink-500';
    const disabledStyles =
        'w-full rounded bg-gray-300 px-4 py-2 font-bold text-gray-400';
    const styles = () => twMerge(
        props.disabled ? disabledStyles : enabledStyles,
        props.class
    );

    return (
        <button
            onClick={props.onClick}
            disabled={props.disabled || false}
            class={styles()}
            type={props.type}
        >
            {props.children}
        </button>
    );
};
