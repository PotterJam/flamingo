import { FC } from 'react';
import { twMerge } from 'tailwind-merge';

interface OutlineButtonProps {
    onClick?: React.MouseEventHandler<HTMLButtonElement>;
    disabled?: boolean;
    children: React.ReactNode;
    type?: any;
    className?: string;
}

export const OutlineButton: FC<OutlineButtonProps> = ({
    onClick,
    disabled = false,
    children,
    type,
    className = '',
}) => {
    const enabledStyles =
        'w-full rounded border-2 border-pink-400 bg-white px-4 py-2 font-bold text-pink-400 hover:bg-pink-100';
    const disabledStyles =
        'w-full rounded bg-gray-300 border-2 border-gray-300 px-4 py-2 font-bold text-gray-400';
    const styles = twMerge(
        disabled ? disabledStyles : enabledStyles,
        className
    );

    return (
        <button
            onClick={onClick}
            disabled={disabled}
            className={styles}
            type={type}
        >
            {children}
        </button>
    );
};


export const FunOutlineButton: FC<OutlineButtonProps> = ({
    onClick,
    disabled = false,
    children,
    className = '',
}) => {
    return (
        <button
            disabled={disabled}
            className={`group relative inline-flex items-center justify-center overflow-hidden rounded-md bg-white px-4 py-2 font-bold text-pink-400 border-2 disabled:border-gray-300 disabled:text-gray-400 border-pink-400 [box-shadow:0px_4px_1px_#f472b6] transition-all active:translate-y-[4px] active:shadow-none disabled:cursor-not-allowed disabled:bg-gray-300 disabled:shadow-none disabled:active:translate-y-0 ${className}`}
            onClick={onClick}
        >
            {children}
        </button>
    );
};
