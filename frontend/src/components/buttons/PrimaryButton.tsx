import { FC } from 'react';
import { twMerge } from 'tailwind-merge';
import { Icon } from '../Icon';

interface PrimaryButtonProps {
    onClick?: React.MouseEventHandler<HTMLButtonElement>;
    disabled?: boolean;
    children: React.ReactNode;
    type?: any;
    className?: string;
    arrow?: boolean;
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

export const FunPrimaryButton: FC<PrimaryButtonProps> = ({
    onClick,
    disabled = false,
    children,
    className = '',
    arrow = false,
}) => {
    return (
        <button
            disabled={disabled}
            className={`group relative inline-flex w-full items-center justify-center overflow-hidden rounded-md bg-pink-400 px-4 py-2 font-bold text-white [box-shadow:0px_4px_1px_#be185d] transition-all active:translate-y-[4px] active:shadow-none disabled:cursor-not-allowed disabled:bg-gray-300 disabled:shadow-none disabled:active:translate-y-0 ${className}`}
            onClick={onClick}
        >
            <span className="flex flex-row items-center gap-3">
                {children}
                {arrow && (
                    <Icon
                        name="clay-arrow-white"
                        size="s"
                        disabled={disabled}
                    />
                )}
            </span>
        </button>
    );
};
