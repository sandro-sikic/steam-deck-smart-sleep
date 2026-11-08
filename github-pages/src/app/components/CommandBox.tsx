import { useState, type ReactNode } from 'react';
import { Copy, Check } from 'lucide-react';

type Accent = 'blue' | 'red';

const ACCENTS: Record<
	Accent,
	{ button: string; glow: string; code: string; hover: string }
> = {
	blue: {
		button:
			'bg-gradient-to-r from-blue-600 to-blue-700 hover:from-blue-500 hover:to-blue-600 shadow-blue-500/20 hover:shadow-blue-500/30',
		glow: 'from-blue-500/5 to-purple-500/5',
		code: 'text-green-400',
		hover: 'hover:shadow-blue-500/10',
	},
	red: {
		button:
			'bg-gradient-to-r from-rose-700 to-red-800 hover:from-rose-600 hover:to-red-700 shadow-red-500/20 hover:shadow-red-500/30',
		glow: 'from-red-500/5 to-slate-500/5',
		code: 'text-rose-300',
		hover: 'hover:shadow-red-500/10',
	},
};

type CommandBoxProps = {
	label: string;
	description: string;
	command: string;
	accent?: Accent;
	children?: ReactNode;
};

export function CommandBox({
	label,
	description,
	command,
	accent = 'blue',
	children,
}: CommandBoxProps) {
	const [copied, setCopied] = useState(false);
	const styles = ACCENTS[accent];

	const handleCopy = async () => {
		await navigator.clipboard.writeText(command);
		setCopied(true);
		setTimeout(() => setCopied(false), 2000);
	};

	return (
		<div className="w-full max-w-3xl">
			<div
				className={`relative bg-gradient-to-br from-slate-800/60 to-slate-900/60 backdrop-blur-md border border-slate-600/50 rounded-2xl p-8 shadow-2xl transition-shadow ${styles.hover}`}
			>
				<div
					className={`absolute inset-0 bg-gradient-to-br ${styles.glow} rounded-2xl`}
				></div>

				<div className="relative">
					<div className="flex items-center justify-between mb-6">
						<div>
							<span className="text-xs font-semibold text-slate-500 uppercase tracking-wider block mb-1">
								{label}
							</span>
							<span className="text-sm text-slate-300">{description}</span>
						</div>
						<button
							onClick={handleCopy}
							className={`flex items-center gap-2 px-5 py-2.5 rounded-lg transition-all font-medium shadow-lg hover:scale-105 ${styles.button}`}
						>
							{copied ? (
								<>
									<Check className="w-4 h-4" />
									Copied!
								</>
							) : (
								<>
									<Copy className="w-4 h-4" />
									Copy
								</>
							)}
						</button>
					</div>

					<div className="bg-slate-950/80 border border-slate-700/50 rounded-xl p-5 overflow-x-auto shadow-inner">
						<code
							className={`${styles.code} font-mono text-sm md:text-base break-all`}
						>
							{command}
						</code>
					</div>

					{children}
				</div>
			</div>
		</div>
	);
}
