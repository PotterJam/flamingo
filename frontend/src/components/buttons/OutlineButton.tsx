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
