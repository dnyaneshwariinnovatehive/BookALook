'use client';

import React, { useEffect, useState, useMemo } from 'react';
import { PageHeader, Alert } from '@/components/admin/ui';
import Icon from '@/components/admin/Icon';
import styles from '../notifications/notifications.module.css';

interface Variable {
    key: string;
    label: string;
    description: string;
    example: string;
}

interface Automation {
    id: string;
    key: string;
    name: string;
    description: string;
    audience: string;
    frequency_label: string;
    is_enabled: boolean;
    aisensy_campaign_name: string | null;
    lead_time_minutes: number | null;
    template_name?: string;
    template_type?: 'pdf' | 'txt';
    variables: Variable[];
    health: {
        status: string;
        last_run_at: string | null;
        last_success_at: string | null;
        last_failure_at: string | null;
    };
}

export default function WhatsappAutomationsPage() {
    const [automations, setAutomations] = useState<Automation[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    // Editing State
    const [editingAutomation, setEditingAutomation] = useState<Automation | null>(null);
    const [editData, setEditData] = useState<{
        is_enabled: boolean;
        aisensy_campaign_name: string;
        lead_time_minutes: number | null;
    } | null>(null);
    const [isSaving, setIsSaving] = useState(false);

    // Test State
    const [testPhone, setTestPhone] = useState('');
    const [isTesting, setIsTesting] = useState(false);

    // Toast System
    const [toast, setToast] = useState<{ type: 'success' | 'error', message: string } | null>(null);

    useEffect(() => {
        fetchAutomations();
    }, []);

    const fetchAutomations = async () => {
        setIsLoading(true);
        setError(null);
        try {
            const response = await fetch('/api/proxy/superadmin/whatsapp-automations');
            if (response.ok) {
                const data = await response.json();
                if (data.success) {
                    setAutomations(data.data || []);
                } else {
                    setError(data.message || 'Failed to load automations.');
                }
            } else {
                setError(`API error: ${response.status} ${response.statusText}`);
            }
        } catch (err: any) {
            console.error('Failed to load automations', err);
            setError(err.message || 'Failed to load automations');
        } finally {
            setIsLoading(false);
        }
    };

    const showToast = (type: 'success' | 'error', message: string) => {
        setToast({ type, message });
        setTimeout(() => setToast(null), 5000);
    };

    const handleEdit = (automation: Automation) => {
        setEditingAutomation(automation);
        setEditData({
            is_enabled: automation.is_enabled,
            aisensy_campaign_name: automation.aisensy_campaign_name || '',
            lead_time_minutes: automation.lead_time_minutes,
        });
        setTestPhone('');
    };

    const closeDrawer = () => {
        setEditingAutomation(null);
        setEditData(null);
    };

    const handleSave = async () => {
        if (!editingAutomation || !editData) return;
        setIsSaving(true);
        try {
            const response = await fetch(`/api/proxy/superadmin/whatsapp-automations/${editingAutomation.key}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(editData),
            });
            const data = await response.json();
            if (response.ok && data.success) {
                await fetchAutomations();
                showToast('success', `${editingAutomation.name} updated successfully.`);
                closeDrawer();
            } else {
                showToast('error', data.message || 'Failed to update automation.');
            }
        } catch (err: any) {
            showToast('error', 'Failed to update automation.');
        } finally {
            setIsSaving(false);
        }
    };

    const handleTest = async () => {
        if (!editingAutomation || !testPhone) {
            showToast('error', 'Please enter a phone number to test.');
            return;
        }

        const campaignToTest = editData?.aisensy_campaign_name || editingAutomation.aisensy_campaign_name;
        if (!campaignToTest) {
            showToast('error', 'Please configure an AiSensy campaign name first.');
            return;
        }

        setIsTesting(true);
        try {
            const response = await fetch(`/api/proxy/superadmin/whatsapp-automations/${editingAutomation.key}/test`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    phone: testPhone,
                    campaign: campaignToTest,
                }),
            });
            const data = await response.json();
            if (response.ok && data.success) {
                showToast('success', 'Test message queued successfully.');
            } else {
                showToast('error', data.message || 'Failed to queue test message.');
            }
        } catch (err: any) {
            showToast('error', 'Failed to send test message.');
        } finally {
            setIsTesting(false);
        }
    };

    const getStatusLabel = (status: string) => {
        switch (status) {
            case 'NOT_CONFIGURED': return 'Not Configured';
            case 'NEEDS_ATTENTION': return 'Needs Attention';
            default: return status.charAt(0) + status.slice(1).toLowerCase();
        }
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'WORKING': return { bg: 'var(--color-success-bg)', text: 'var(--color-success)' };
            case 'READY': return { bg: 'var(--accent-soft)', text: 'var(--accent-text)' };
            case 'DISABLED': return { bg: 'var(--surface-3)', text: 'var(--text-muted)' };
            case 'NOT_CONFIGURED': return { bg: 'var(--color-danger-bg)', text: 'var(--color-danger)' };
            case 'NEEDS_ATTENTION': return { bg: 'var(--color-warning-bg)', text: 'var(--color-warning)' };
            case 'FAILING': return { bg: 'var(--color-danger-bg)', text: 'var(--color-danger)' };
            default: return { bg: 'var(--surface-3)', text: 'var(--text-muted)' };
        }
    };

    const activeCount = useMemo(() => automations.filter(a => a.is_enabled).length, [automations]);

    return (
        <div style={{ padding: '32px', maxWidth: '1200px', margin: '0 auto', color: 'var(--text-body)' }}>
            {toast && (
                <div style={{ position: 'fixed', bottom: 24, right: 24, zIndex: 9999 }}>
                    <Alert tone={toast.type} onClose={() => setToast(null)}>{toast.message}</Alert>
                </div>
            )}

            <div className={styles.header} style={{ marginBottom: 32 }}>
                <div>
                    <h1 style={{ fontSize: 24, fontWeight: 600, color: 'var(--text-heading)', marginBottom: 4 }}>WhatsApp Automations</h1>
                    <p style={{ color: 'var(--text-muted)', margin: 0 }}>Manage automated system WhatsApp messages sent by BookALook.</p>
                </div>
                {!isLoading && automations.length > 0 && (
                    <div style={{ fontSize: 13, color: 'var(--text-strong)', background: 'var(--surface-2)', padding: '6px 12px', borderRadius: 8, border: '1px solid var(--border-color)' }}>
                        {automations.length} Automations &middot; <span style={{ fontWeight: 600, color: activeCount > 0 ? 'var(--color-success)' : 'var(--text-muted)' }}>{activeCount} Active</span> &middot; {automations.length - activeCount} Disabled
                    </div>
                )}
            </div>

            {isLoading ? (
                <div className={styles.dashboardCards} style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))' }}>
                    {[1, 2, 3, 4].map(i => (
                        <div key={i} className={styles.card} style={{ minHeight: 200, display: 'flex', flexDirection: 'column', gap: 16 }}>
                            <div style={{ background: 'var(--surface-2)', height: 24, width: '40%', borderRadius: 4 }} />
                            <div style={{ background: 'var(--surface-2)', height: 16, width: '80%', borderRadius: 4 }} />
                            <div style={{ background: 'var(--surface-2)', height: 48, width: '100%', borderRadius: 4 }} />
                        </div>
                    ))}
                </div>
            ) : error ? (
                <Alert tone="error">
                    <strong>Error loading automations</strong><br />
                    {error}
                    <div style={{ marginTop: 12 }}>
                        <button className={styles.testBtn} onClick={fetchAutomations}>Retry</button>
                    </div>
                </Alert>
            ) : automations.length === 0 ? (
                <div className={styles.card} style={{ textAlign: 'center', padding: '64px 20px' }}>
                    <Icon name="info" size={32} style={{ color: 'var(--text-muted)', marginBottom: 16 }} />
                    <h3 style={{ fontSize: 18, color: 'var(--text-heading)', margin: '0 0 8px 0' }}>No automations configured</h3>
                    <p style={{ color: 'var(--text-muted)', margin: 0 }}>System WhatsApp messages will appear here once properly seeded in the database.</p>
                </div>
            ) : (
                <div className={styles.dashboardCards} style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(400px, 1fr))' }}>
                    {automations.map((automation) => {
                        const statusColor = getStatusColor(automation.health.status);
                        return (
                            <div key={automation.key} className={styles.card} style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 12 }}>
                                    <div style={{ fontWeight: 600, fontSize: 16, color: 'var(--text-heading)' }}>{automation.name}</div>
                                    <span style={{ 
                                        padding: '4px 10px', 
                                        borderRadius: 9999, 
                                        fontSize: 12, 
                                        fontWeight: 500,
                                        background: statusColor.bg,
                                        color: statusColor.text
                                    }}>
                                        {getStatusLabel(automation.health.status)}
                                    </span>
                                </div>
                                
                                <p style={{ fontSize: 14, color: 'var(--text-body)', marginBottom: 24, flex: 1 }}>
                                    {automation.description}
                                </p>
                                
                                <div style={{ marginBottom: 16 }}>
                                    <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-heading)', display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                                        <Icon name="users" size={14} style={{ color: 'var(--text-muted)' }} /> {automation.audience}
                                    </div>
                                    <div style={{ fontSize: 13, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                                        <Icon name="clock" size={14} style={{ color: 'var(--text-muted)' }} /> {automation.frequency_label}
                                    </div>
                                    <div style={{ fontSize: 13, color: 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 6 }}>
                                        <Icon name="checkCircle" size={14} style={{ color: automation.aisensy_campaign_name ? 'var(--color-success)' : 'var(--border-strong)' }} />
                                        Campaign: {automation.aisensy_campaign_name ? (
                                            <span style={{ color: 'var(--text-heading)', fontWeight: 500, display: 'inline-flex', alignItems: 'center', gap: 6 }}>
                                                {automation.aisensy_campaign_name}
                                                {automation.template_type === 'pdf' ? (
                                                    <span style={{ fontSize: 10, background: 'var(--color-danger-bg)', color: 'var(--color-danger)', padding: '1px 5px', borderRadius: 4, fontWeight: 700 }}>PDF</span>
                                                ) : (
                                                    <span style={{ fontSize: 10, background: 'var(--surface-3)', color: 'var(--text-muted)', padding: '1px 5px', borderRadius: 4, fontWeight: 600 }}>TXT</span>
                                                )}
                                            </span>
                                        ) : <span style={{ fontStyle: 'italic' }}>Not configured</span>}
                                    </div>
                                </div>
                                
                                <div style={{ borderTop: '1px solid var(--border-color)', margin: '0 -20px 0 -20px', padding: '16px 20px 0 20px', display: 'flex', justifyContent: 'flex-end' }}>
                                    <button className={styles.editBtn} onClick={() => handleEdit(automation)}>Configure &rarr;</button>
                                </div>
                            </div>
                        );
                    })}
                </div>
            )}

            {/* Editor Drawer */}
            {editingAutomation && editData && (
                <div className={styles.drawerOverlay}>
                    <div className={styles.drawerContent} style={{ maxWidth: 640 }}>
                        <div className={styles.drawerHeader}>
                            <div>
                                <h2>{editingAutomation.name}</h2>
                                <p>System WhatsApp Automation</p>
                            </div>
                            <button className={styles.closeBtn} onClick={closeDrawer}>&times;</button>
                        </div>
                        
                        <div className={styles.drawerBody} style={{ flexDirection: 'column', gap: 24 }}>
                            
                            {/* Automation Status */}
                            <div className={styles.sectionBox} style={{ borderLeft: editingAutomation.is_enabled ? '4px solid var(--color-success)' : '4px solid var(--border-strong)' }}>
                                <h3 style={{ marginBottom: 16 }}>Automation</h3>
                                
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                                    <div>
                                        <div style={{ fontWeight: 500, fontSize: 14, color: 'var(--text-heading)', marginBottom: 4 }}>Status</div>
                                        {editingAutomation.key === 'whatsapp_otp' ? (
                                            <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>
                                                Send real OTPs via WhatsApp when enabled. When disabled, the demo 123456 OTP is used.
                                            </div>
                                        ) : (
                                            <div style={{ fontSize: 13, color: 'var(--text-muted)' }}>Allow the system to send WhatsApp messages when this event occurs.</div>
                                        )}
                                    </div>
                                    <label className={styles.toggleSwitch} style={{ cursor: 'pointer' }}>
                                        <input 
                                            type="checkbox" 
                                            checked={editData.is_enabled}
                                            onChange={(e) => setEditData({...editData, is_enabled: e.target.checked})}
                                        />
                                        <span className={styles.slider}></span>
                                    </label>
                                </div>

                                <div style={{ display: 'flex', gap: 48, borderTop: '1px solid var(--border-color)', paddingTop: 16 }}>
                                    <div>
                                        <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4 }}>Audience</div>
                                        <div style={{ fontSize: 14, color: 'var(--text-heading)' }}>{editingAutomation.audience}</div>
                                    </div>
                                    <div>
                                        <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.05em', marginBottom: 4 }}>Trigger</div>
                                        <div style={{ fontSize: 14, color: 'var(--text-heading)', display: 'flex', alignItems: 'center', gap: 6 }}>
                                            {editingAutomation.frequency_label}
                                            {(editingAutomation.key === 'whatsapp_customer_birthday' || editingAutomation.key === 'whatsapp_25_day_reminder') && (
                                                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, background: 'var(--surface-3)', padding: '2px 6px', borderRadius: 4, fontSize: 11, color: 'var(--text-muted)' }}>
                                                    <Icon name="info" size={10} /> System rule
                                                </span>
                                            )}
                                        </div>
                                    </div>
                                </div>
                            </div>

                            {/* AiSensy Configuration */}
                            <div className={styles.sectionBox}>
                                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                                    <h3 style={{ margin: 0 }}>AiSensy</h3>
                                    {editData.aisensy_campaign_name ? (
                                        <span style={{ fontSize: 12, fontWeight: 500, color: 'var(--color-success)', display: 'flex', alignItems: 'center', gap: 4 }}>
                                            <div style={{ width: 6, height: 6, borderRadius: 3, background: 'var(--color-success)' }} /> Configured
                                        </span>
                                    ) : (
                                        <span style={{ fontSize: 12, fontWeight: 500, color: editingAutomation.is_enabled ? 'var(--color-danger)' : 'var(--text-muted)', display: 'flex', alignItems: 'center', gap: 4 }}>
                                            <div style={{ width: 6, height: 6, borderRadius: 3, background: editingAutomation.is_enabled ? 'var(--color-danger)' : 'var(--text-muted)' }} /> No campaign configured
                                        </span>
                                    )}
                                </div>
                                
                                <div className={styles.formGroup}>
                                    <label>Campaign Name</label>
                                    <input 
                                        type="text" 
                                        className={styles.input}
                                        value={editData.aisensy_campaign_name}
                                        onChange={(e) => setEditData({...editData, aisensy_campaign_name: e.target.value})}
                                        placeholder="e.g. bal_apt_reminder"
                                    />
                                    <p style={{ fontSize: 12, color: 'var(--text-muted)', margin: '4px 0 0 0' }}>
                                        Approved AiSensy campaign name exactly as in AiSensy dashboard.
                                        {editingAutomation.template_name && (
                                            <> (Meta Template: <code>{editingAutomation.template_name}</code> &middot; <strong>{editingAutomation.template_type?.toUpperCase()}</strong>)</>
                                        )}
                                    </p>
                                </div>

                                {editingAutomation.key === 'whatsapp_appointment_reminder' && (
                                    <div className={styles.formGroup} style={{ marginTop: 20 }}>
                                        <label>Reminder timing (Minutes)</label>
                                        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                                            <input 
                                                type="number" 
                                                className={styles.input}
                                                style={{ width: 100 }}
                                                value={editData.lead_time_minutes || ''}
                                                onChange={(e) => setEditData({...editData, lead_time_minutes: parseInt(e.target.value) || 0})}
                                                min="1"
                                            />
                                            <span style={{ fontSize: 14, color: 'var(--text-body)' }}>minutes before appointment</span>
                                        </div>
                                        <p style={{ fontSize: 12, color: 'var(--text-muted)', margin: '4px 0 0 0' }}>Customers will receive the reminder within the existing scheduler window (typically batched).</p>
                                    </div>
                                )}
                            </div>

                            {/* Variables */}
                            <div className={styles.sectionBox}>
                                <h3 style={{ marginBottom: 16 }}>Variables</h3>
                                {editingAutomation.variables.length === 0 ? (
                                    <p style={{ fontSize: 13, color: 'var(--text-muted)', margin: 0 }}>No variables are required for this automation.</p>
                                ) : (
                                    <>
                                        <p style={{ fontSize: 13, color: 'var(--text-muted)', margin: '0 0 16px 0' }}>Required variables &middot; exact order</p>
                                        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                                            {editingAutomation.variables.map((v, i) => (
                                                <div key={v.key} style={{ display: 'flex', gap: 12, padding: 12, background: 'var(--surface-2)', borderRadius: 8, border: '1px solid var(--border-color)' }}>
                                                    <div style={{ fontWeight: 600, color: 'var(--text-muted)', fontSize: 13 }}>{i + 1}.</div>
                                                    <div style={{ flex: 1 }}>
                                                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                                                            <code style={{ background: 'var(--surface-color)', padding: '2px 6px', borderRadius: 4, fontSize: 13, border: '1px solid var(--border-color)', color: 'var(--text-heading)', fontWeight: 500 }}>
                                                                {v.key}
                                                            </code>
                                                        </div>
                                                        <div style={{ fontSize: 13, color: 'var(--text-body)', marginBottom: 4 }}>{v.description}</div>
                                                        <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                                                            Example: <span style={{ color: 'var(--text-heading)', fontWeight: 500 }}>{v.key} &rarr; {v.example}</span>
                                                        </div>
                                                    </div>
                                                </div>
                                            ))}
                                        </div>
                                    </>
                                )}
                            </div>

                            {/* Test Campaign */}
                            <div className={styles.sectionBox}>
                                <h3 style={{ marginBottom: 16 }}>Test</h3>
                                <p style={{ fontSize: 13, color: 'var(--text-muted)', margin: '0 0 16px 0' }}>
                                    Send a test WhatsApp to verify the campaign before turning it on.
                                    {editingAutomation.template_type === 'pdf' && (
                                        <span> Test sends a sample PDF document attachment.</span>
                                    )}
                                </p>
                                
                                <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                                    <div style={{ flex: 1 }} className={styles.formGroup}>
                                        <input 
                                            type="text" 
                                            className={styles.input}
                                            value={testPhone}
                                            onChange={(e) => setTestPhone(e.target.value)}
                                            placeholder="+91XXXXXXXXXX"
                                            disabled={!editData.aisensy_campaign_name}
                                        />
                                    </div>
                                    <div style={{ marginTop: '-20px' }}>
                                        <button 
                                            className={styles.testBtn} 
                                            onClick={handleTest}
                                            disabled={isTesting || !editData.aisensy_campaign_name}
                                            style={{ opacity: (!editData.aisensy_campaign_name) ? 0.5 : 1 }}
                                        >
                                            {isTesting ? 'Sending...' : 'Send Test'}
                                        </button>
                                    </div>
                                </div>
                                
                                {!editData.aisensy_campaign_name && (
                                    <p style={{ fontSize: 12, color: 'var(--text-muted)', margin: '8px 0 0 0' }}>
                                        Configure an AiSensy campaign name to test.
                                    </p>
                                )}
                            </div>

                        </div>
                        
                        <div className={styles.drawerFooter}>
                            <button className={styles.editBtn} onClick={closeDrawer}>Cancel</button>
                            <button className={styles.saveBtn} onClick={handleSave} disabled={isSaving}>
                                {isSaving ? 'Saving...' : 'Save Changes'}
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
