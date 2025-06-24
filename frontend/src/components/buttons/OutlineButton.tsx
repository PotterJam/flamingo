import { JSX } from 'solid-js';
import { twMerge } from 'tailwind-merge';

export interface OutlineButtonProps {
    onClick?: () => void;
    disabled?: boolean;
    children: JSX.Element;
    type?: string;
    class?: string;
}

export const OutlineButton = (props: OutlineButtonProps) => {
    const enabledStyles =
        'w-full rounded border-2 border-pink-400 bg-white px-4 py-2 font-bold text-pink-400 hover:bg-pink-100';
    const disabledStyles =
        'w-full rounded bg-gray-300 border-2 border-gray-300 px-4 py-2 font-bold text-gray-400';
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
