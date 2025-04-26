import { FC } from 'react';
import { twMerge } from 'tailwind-merge';

interface PrimaryButtonProps {
    onClick?: React.MouseEventHandler<HTMLButtonElement>;
    disabled?: boolean;
    children: React.ReactNode;
    type?: any;
    className?: string;
}

export const PrimaryButton: FC<PrimaryButtonProps> = ({
    onClick,
    disabled = false,
    children,
    type,
    className = '',
}) => {
    const enabledStyles =
        'w-full rounded bg-pink-400 px-4 py-2 font-bold text-white hover:bg-pink-500';
    const disabledStyles =
        'w-full rounded bg-gray-300 px-4 py-2 font-bold text-gray-400';
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
